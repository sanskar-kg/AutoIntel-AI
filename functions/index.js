const crypto = require('node:crypto');
const {onRequest} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {FieldValue, getFirestore, Timestamp} = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

const TOKEN_URL = process.env.TRUECALLER_TOKEN_URL ||
  'https://oauth-account-noneu.truecaller.com/v1/token';
const USERINFO_URL = process.env.TRUECALLER_USERINFO_URL ||
  'https://oauth-account-noneu.truecaller.com/v1/userinfo';
const CLIENT_ID = process.env.TRUECALLER_CLIENT_ID;

exports.authApi = onRequest({cors: true, region: 'asia-south1'}, async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  if (req.method === 'POST' && req.path === '/v1/auth/truecaller') {
    await handleTruecallerAuth(req, res);
    return;
  }
  if (req.method === 'POST' && req.path === '/v1/auth/anonymous') {
    await handleAnonymousAuth(req, res);
    return;
  }

  try {
    const accountId = await requireSession(req);
    await handleAuthenticatedRoute(req, res, accountId);
  } catch (error) {
    console.error('Authenticated API request failed', {
      path: req.path,
      name: error?.name,
      message: error?.message,
    });
    const status = error?.code === 'UNAUTHENTICATED' ? 401 :
      error?.code === 'NOT_FOUND' ? 404 : 400;
    res.status(status).json({error: error?.code || 'REQUEST_FAILED'});
  }
});

async function handleTruecallerAuth(req, res) {
  try {
    const {authorizationCode, codeVerifier, state, scopesGranted} = req.body || {};
    if (!CLIENT_ID || !authorizationCode || !codeVerifier || !state ||
        !Array.isArray(scopesGranted) || !scopesGranted.includes('openid')) {
      res.status(400).json({error: 'INVALID_AUTH_REQUEST'});
      return;
    }

    const tokenResponse = await fetch(TOKEN_URL, {
      method: 'POST',
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        client_id: CLIENT_ID,
        code: authorizationCode,
        code_verifier: codeVerifier,
      }),
    });
    if (!tokenResponse.ok) {
      res.status(401).json({error: 'TRUECALLER_CODE_REJECTED'});
      return;
    }
    const token = await tokenResponse.json();
    if (!token.access_token) {
      res.status(502).json({error: 'TRUECALLER_TOKEN_MISSING'});
      return;
    }

    const profileResponse = await fetch(USERINFO_URL, {
      headers: {
        authorization: `Bearer ${token.access_token}`,
        'cache-control': 'no-cache',
      },
    });
    if (!profileResponse.ok) {
      res.status(401).json({error: 'TRUECALLER_PROFILE_REJECTED'});
      return;
    }
    const profile = await profileResponse.json();
    const account = await upsertAccount(profile, state);
    const sessionToken = createSessionToken();
    await storeSession(sessionToken, account.id);

    res.status(200).json({
      sessionToken,
      account: {
        id: account.id,
        name: account.name,
        phone: account.phone,
        provider: 'truecaller',
        isTemporary: false,
        isPhoneVerified: true,
      },
    });
  } catch (error) {
    console.error('Truecaller authentication failed', {
      name: error?.name,
      message: error?.message,
    });
    res.status(500).json({error: 'AUTHENTICATION_FAILED'});
  }
}

async function handleAnonymousAuth(req, res) {
  try {
    const header = String(req.get('Authorization') || '');
    const idToken = header.startsWith('Bearer ') ? header.substring(7).trim() : '';
    if (!idToken) {
      res.status(401).json({error: 'UNAUTHENTICATED'});
      return;
    }
    const decoded = await getAuth().verifyIdToken(idToken);
    const account = await upsertAnonymousAccount(decoded.uid);
    const sessionToken = createSessionToken();
    await storeSession(sessionToken, account.id);
    res.status(200).json({
      sessionToken,
      account: {
        id: account.id,
        name: 'Temporary account',
        provider: 'firebase_anonymous',
        isTemporary: true,
        isPhoneVerified: false,
      },
    });
  } catch (error) {
    console.error('Anonymous authentication failed', {message: error?.message});
    res.status(401).json({error: 'UNAUTHENTICATED'});
  }
}

/*
 * The authenticated API is deliberately server-authoritative. The app can
 * request a wallet snapshot and create an order, but cannot write a balance.
 * PayU must call a verified webhook before an order is credited.
 */
async function handleAuthenticatedRoute(req, res, accountId) {
  if (req.method === 'GET' && req.path === '/v1/config') {
    res.json({
      rcPricePaise: 200,
      phonePricePaise: 500,
      minRechargePaise: 2000,
      maxRechargePaise: 1000000,
      presetsPaise: [5000, 10000, 20000, 50000],
    });
    return;
  }

  const wallet = await ensureWallet(accountId);
  if (req.method === 'GET' && req.path === '/v1/wallet') {
    const firstLoad = await consumeWalletOnboardingGate(accountId);
    res.json(walletJson({...wallet, showRechargeGate: firstLoad}));
    return;
  }
  if (req.method === 'GET' && req.path === '/v1/wallet/ledger') {
    const snapshot = await db.collection(`wallets/${accountId}/ledger`)
      .orderBy('createdAt', 'desc').limit(100).get();
    res.json({entries: snapshot.docs.map((doc) => ledgerJson(doc.id, doc.data()))});
    return;
  }
  if (req.method === 'POST' && req.path === '/v1/wallet/orders') {
    const amountPaise = Number(req.body?.amountPaise);
    if (!Number.isSafeInteger(amountPaise) || amountPaise < 2000 || amountPaise > 1000000) {
      throw apiError('PAYMENT_FAILED');
    }
    const idempotencyKey = String(req.get('Idempotency-Key') || '').trim();
    if (idempotencyKey) {
      const prior = await db.doc(`wallet_order_keys/${accountId}:${sha256(idempotencyKey)}`).get();
      if (prior.exists) {
        const existing = await db.doc(`wallet_orders/${prior.get('orderId')}`).get();
        if (existing.exists) {
          res.json(orderJson(existing.id, existing.data()));
          return;
        }
      }
    }
    const orderRef = db.collection('wallet_orders').doc();
    const order = {
      accountId,
      amountPaise,
      status: 'created',
      gateway: 'PAYU',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };
    const batch = db.batch();
    batch.set(orderRef, order);
    if (idempotencyKey) {
      batch.set(db.doc(`wallet_order_keys/${accountId}:${sha256(idempotencyKey)}`), {
        accountId, orderId: orderRef.id, createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    res.status(201).json(orderJson(orderRef.id, {...order, status: 'created'}));
    return;
  }

  const orderMatch = req.path.match(/^\/v1\/wallet\/orders\/([^/]+)(?:\/(gateway-result))?$/);
  if (orderMatch) {
    const orderRef = db.doc(`wallet_orders/${orderMatch[1]}`);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists || orderSnap.get('accountId') !== accountId) throw apiError('NOT_FOUND');
    if (req.method === 'GET' && !orderMatch[2]) {
      res.json(orderJson(orderSnap.id, orderSnap.data()));
      return;
    }
    if (req.method === 'POST' && orderMatch[2]) {
      const status = String(req.body?.status || 'pending');
      const next = status === 'failed' ? 'failed' : 'pending';
      await orderRef.update({status: next, updatedAt: FieldValue.serverTimestamp(), clientCallbackAt: FieldValue.serverTimestamp()});
      res.json({ok: true});
      return;
    }
  }

  if (req.method === 'POST' && req.path === '/v1/lookup') {
    await handleLookup(req, res, accountId, wallet);
    return;
  }
  throw apiError('NOT_FOUND');
}

async function ensureWallet(accountId) {
  const ref = db.doc(`wallets/${accountId}`);
  const snap = await ref.get();
  if (snap.exists) return snap.data();
  const data = {
    accountId, currency: 'INR', status: 'active', balancePaise: 0,
    minRechargeDone: false, version: 0, createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.set(data, {merge: true});
  return {...data, balancePaise: 0, minRechargeDone: false, version: 0};
}

async function consumeWalletOnboardingGate(accountId) {
  const walletRef = db.doc(`wallets/${accountId}`);
  let firstLoad = false;
  await db.runTransaction(async (transaction) => {
    const wallet = await transaction.get(walletRef);
    firstLoad = wallet.get('walletOnboardingCompleted') !== true;
    if (firstLoad) {
      transaction.update(walletRef, {
        walletOnboardingCompleted: true,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
  return firstLoad;
}

async function handleLookup(req, res, accountId, wallet) {
  const type = String(req.body?.type || '');
  const regNo = String(req.body?.regNo || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  const pricePaise = type === 'rc' ? 200 : type === 'phone' ? 500 : 0;
  if (!pricePaise || !/^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$/.test(regNo)) throw apiError('INVALID_REG_NO');
  if (!wallet.minRechargeDone) throw apiError('RECHARGE_REQUIRED');
  if (wallet.balancePaise < pricePaise) throw apiError('INSUFFICIENT_BALANCE');

  const walletRef = db.doc(`wallets/${accountId}`);
  const ledgerRef = walletRef.collection('ledger').doc();
  const now = new Date().toISOString();
  const balanceAfterPaise = wallet.balancePaise - pricePaise;
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(walletRef);
    const currentBalance = Number(current.get('balancePaise') || 0);
    if (currentBalance < pricePaise) throw apiError('INSUFFICIENT_BALANCE');
    transaction.update(walletRef, {
      balancePaise: currentBalance - pricePaise,
      version: Number(current.get('version') || 0) + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(ledgerRef, {
      type: 'debit', category: type === 'rc' ? 'rcLookup' : 'phoneLookup',
      amountPaise: pricePaise, balanceAfterPaise: currentBalance - pricePaise,
      createdAt: FieldValue.serverTimestamp(), regNoMasked: maskRegNo(regNo),
    });
  });
  const result = type === 'rc' ? {
    id: crypto.randomUUID(), type, regNo, regNoMasked: maskRegNo(regNo),
    chargedPaise: pricePaise, createdAt: now, isDemo: true,
    rc: {ownerName: 'Provider pending', maker: 'Provider pending', model: 'Provider pending', extra: {}},
  } : {
    id: crypto.randomUUID(), type, regNo, regNoMasked: maskRegNo(regNo),
    chargedPaise: pricePaise, createdAt: now, isDemo: true, phone: '0000000000',
  };
  res.json(result);
}

function walletJson(wallet) {
  return {
    balancePaise: Number(wallet.balancePaise || 0),
    minRechargeDone: wallet.minRechargeDone === true,
    showRechargeGate: wallet.showRechargeGate === true,
  };
}

function ledgerJson(id, data) {
  return {
    id, type: data.type, category: data.category,
    amountPaise: Number(data.amountPaise || 0),
    balanceAfterPaise: Number(data.balanceAfterPaise || 0),
    createdAt: data.createdAt?.toDate?.().toISOString() || new Date().toISOString(),
    regNoMasked: data.regNoMasked || '',
  };
}

function orderJson(id, data) {
  return {
    id, amountPaise: Number(data.amountPaise || 0),
    status: data.status, gateway: data.gateway || 'PAYU',
  };
}

async function requireSession(req) {
  const header = String(req.get('Authorization') || '');
  const token = header.startsWith('Bearer ') ? header.substring(7).trim() : '';
  if (!token) throw apiError('UNAUTHENTICATED');
  const snap = await db.doc(`auth_sessions/${sha256(token)}`).get();
  if (!snap.exists || snap.get('revokedAt')) throw apiError('UNAUTHENTICATED');
  const expiresAt = snap.get('expiresAt')?.toDate?.();
  if (!expiresAt || expiresAt.getTime() <= Date.now()) throw apiError('UNAUTHENTICATED');
  return snap.get('accountId');
}

function apiError(code) {
  const error = new Error(code);
  error.code = code;
  return error;
}

function maskRegNo(value) {
  if (value.length <= 4) return value;
  return `${value.substring(0, value.length - 4)}****`;
}

async function upsertAccount(profile, state) {
  const subject = String(profile.sub || '');
  const phone = normalizePhone(
    profile.phone_number,
    profile.phone_number_country_code,
  );
  const name = [profile.given_name, profile.family_name]
    .filter(Boolean).join(' ').trim();
  if (!subject || !phone || !name || profile.phone_number_verified !== true) {
    throw new Error('Incomplete or unverified Truecaller profile');
  }

  const identityRef = db.doc(`account_identities/truecaller:${subject}`);
  const accountRef = db.collection('accounts').doc();
  const now = FieldValue.serverTimestamp();
  const existing = await identityRef.get();
  const resolvedAccountRef = existing.exists ?
    db.doc(`accounts/${existing.get('accountId')}`) : accountRef;

  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(resolvedAccountRef);
    const walletRef = db.doc(`wallets/${resolvedAccountRef.id}`);
    const wallet = await transaction.get(walletRef);
    transaction.set(resolvedAccountRef, {
      name,
      phone,
      truecallerSubject: subject,
      provider: 'truecaller',
      phoneVerified: true,
      lastLoginAt: now,
      lastAuthStateHash: sha256(state),
      ...(current.exists ? {} : {createdAt: now, status: 'active'}),
    }, {merge: true});
    transaction.set(walletRef, {
      accountId: resolvedAccountRef.id,
      currency: 'INR',
      updatedAt: now,
      ...(wallet.exists ? {} : {
        balancePaise: 0,
        minRechargeDone: false,
        walletOnboardingCompleted: false,
        version: 0,
        createdAt: now,
      }),
    }, {merge: true});
    transaction.set(identityRef, {
      accountId: resolvedAccountRef.id,
      provider: 'truecaller',
      subject,
      updatedAt: now,
    }, {merge: true});
  });
  return {id: resolvedAccountRef.id, name, phone};
}

async function upsertAnonymousAccount(uid) {
  const accountId = `firebase_${uid}`;
  const accountRef = db.doc(`accounts/${accountId}`);
  const walletRef = db.doc(`wallets/${accountId}`);
  const now = FieldValue.serverTimestamp();
  await db.runTransaction(async (transaction) => {
    const wallet = await transaction.get(walletRef);
    transaction.set(accountRef, {
      name: 'Temporary account', provider: 'firebase_anonymous',
      phoneVerified: false, firebaseUid: uid, lastLoginAt: now,
      ...(wallet.exists ? {} : {createdAt: now, status: 'active'}),
    }, {merge: true});
    transaction.set(walletRef, {
      accountId, currency: 'INR', updatedAt: now,
      ...(wallet.exists ? {} : {
        balancePaise: 0,
        minRechargeDone: false,
        walletOnboardingCompleted: false,
        version: 0,
        createdAt: now,
      }),
    }, {merge: true});
  });
  return {id: accountId};
}

async function storeSession(token, accountId) {
  const expiresAt = Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await db.doc(`auth_sessions/${sha256(token)}`).set({
    accountId,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
    revokedAt: null,
  });
}

function normalizePhone(value, countryCode) {
  const raw = String(value || '').trim();
  const digits = raw.replace(/[^0-9]/g, '');
  const international = `+${digits}`;
  if (raw.startsWith('+') && /^\+[1-9][0-9]{7,14}$/.test(international)) {
    return international;
  }

  const countryValue = String(countryCode || '').trim().toUpperCase();
  const countryDigits = (countryValue === 'IN' ? '91' : countryValue)
    .replace(/[^0-9]/g, '')
    .replace(/^0+/, '');
  if (countryDigits && digits.startsWith(countryDigits)) {
    const normalized = `+${digits}`;
    if (/^\+[1-9][0-9]{7,14}$/.test(normalized)) return normalized;
  }
  if (countryDigits === '91' && /^[6-9][0-9]{9}$/.test(digits)) {
    return `+91${digits}`;
  }
  throw new Error('Invalid phone');
}

function createSessionToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}
