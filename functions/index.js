const crypto = require('node:crypto');
const {onRequest} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {FieldValue, getFirestore, Timestamp} = require('firebase-admin/firestore');
const {getRemoteConfig} = require('firebase-admin/remote-config');

initializeApp();
const db = getFirestore();

const TOKEN_URL = process.env.TRUECALLER_TOKEN_URL ||
  'https://oauth-account-noneu.truecaller.com/v1/token';
const USERINFO_URL = process.env.TRUECALLER_USERINFO_URL ||
  'https://oauth-account-noneu.truecaller.com/v1/userinfo';
const CLIENT_ID = process.env.TRUECALLER_CLIENT_ID;
const PAYU_MERCHANT_KEY = defineSecret('PAYU_MERCHANT_KEY');
const PAYU_MERCHANT_SALT = defineSecret('PAYU_MERCHANT_SALT');
const CSTUDIO_RCPLUS_KEY = defineSecret('CSTUDIO_RCPLUS_KEY');
const CSTUDIO_RC2NUM_KEY = defineSecret('CSTUDIO_RC2NUM_KEY');
const CSTUDIO_API_BASE_URL = 'https://apiv2.cstudio.sbs/';

const DEFAULT_LOOKUP_PRICES = Object.freeze({
  rcPricePaise: 200,
  phonePricePaise: 700,
  minRechargePaise: 2000,
});
let lookupPricesCache = null;
let lookupPricesCachedAt = 0;
const LOOKUP_PRICES_CACHE_MS = 60 * 1000;

exports.authApi = onRequest({
  cors: true,
  region: 'asia-south1',
  secrets: [
    PAYU_MERCHANT_KEY,
    PAYU_MERCHANT_SALT,
    CSTUDIO_RCPLUS_KEY,
    CSTUDIO_RC2NUM_KEY,
  ],
}, async (req, res) => {
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
  if (req.method === 'POST' && req.path === '/v1/webhooks/payu/success') {
    await handlePayUPaymentWebhook(req, res, 'success');
    return;
  }
  if (req.method === 'POST' && req.path === '/v1/webhooks/payu/failed') {
    await handlePayUPaymentWebhook(req, res, 'failed');
    return;
  }
  if (req.method === 'POST' && req.path === '/v1/webhooks/payu/refund') {
    await handlePayURefundWebhook(req, res);
    return;
  }
  if (req.method === 'POST' && req.path === '/v1/webhooks/payu/dispute') {
    await handlePayUDisputeWebhook(req, res);
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
  if (req.method === 'POST' && req.path === '/v1/payments/payu/hash') {
    await handlePayUHash(req, res);
    return;
  }
  if (req.method === 'GET' && req.path === '/v1/config') {
    const prices = await getLookupPrices();
    res.json({
      ...prices,
      minRechargePaise: prices.minRechargePaise,
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
    const prices = await getLookupPrices();
    if (!Number.isSafeInteger(amountPaise) ||
        amountPaise < prices.minRechargePaise ||
        amountPaise > 1000000) {
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

async function handlePayUHash(req, res) {
  const response = req.body?.response;
  const hashName = String(response?.hashName || '').trim();
  const hashString = String(response?.hashString || '');
  const hashType = String(response?.hashType || '');
  const postSalt = String(response?.postSalt || '');
  if (!hashName || !hashString) throw apiError('PAYMENT_FAILED');

  const salt = PAYU_MERCHANT_SALT.value();
  if (!salt) throw apiError('PAYMENT_FAILED');

  let hash;
  if (/v2/i.test(hashType)) {
    hash = crypto.createHmac('sha256', salt).update(hashString).digest('base64');
  } else {
    hash = sha512(`${hashString}${salt}${postSalt}`);
  }
  res.json({[hashName]: hash});
}

async function handlePayUPaymentWebhook(req, res, expectedEvent) {
  try {
    const payload = normalizePayUPayload(req.body);
    const key = PAYU_MERCHANT_KEY.value();
    const salt = PAYU_MERCHANT_SALT.value();
    if (!key || !salt || payload.key !== key || !payload.hash) {
      res.status(401).send('Invalid webhook credentials');
      return;
    }
    if (!verifyPayUResponseHash(payload, salt)) {
      res.status(401).send('Invalid webhook hash');
      return;
    }

    const requestedStatus = String(payload.status || '').toLowerCase();
    const isExpectedStatus = expectedEvent === 'success' ?
      requestedStatus === 'success' : requestedStatus === 'failure';
    if (!isExpectedStatus) {
      res.status(400).send('Webhook event does not match endpoint');
      return;
    }

    const orderId = String(payload.udf1 || '').trim();
    const txnid = String(payload.txnid || '').trim();
    if (!orderId || !txnid) throw apiError('PAYMENT_FAILED');

    const verified = await verifyPayUPayment(txnid, key, salt);
    const verifiedStatus = String(verified.status || '').toLowerCase();
    const amountPaise = Math.round(Number(payload.amount || 0) * 100);
    const status = verifiedStatus === 'success' && requestedStatus === 'success' ?
      'success' : requestedStatus === 'failure' ? 'failed' : 'pending';

    await settlePayUOrder(orderId, txnid, amountPaise, status, payload, verified);
    res.status(200).send('OK');
  } catch (error) {
    console.error('PayU webhook processing failed', {
      name: error?.name,
      message: error?.message,
    });
    res.status(500).send('Webhook processing failed');
  }
}

async function handlePayURefundWebhook(req, res) {
  try {
    const payload = normalizePayUJsonPayload(req.body);
    const key = PAYU_MERCHANT_KEY.value();
    const salt = PAYU_MERCHANT_SALT.value();
    if (!key || !salt || String(payload.key || '').trim() !== key) {
      res.status(401).send('Invalid webhook credentials');
      return;
    }
    if (String(payload.action || '').toLowerCase() !== 'refund') {
      res.status(400).send('Unsupported refund event');
      return;
    }
    await handlePayURefund(payload);
    res.status(200).send('OK');
  } catch (error) {
    console.error('PayU refund webhook processing failed', {
      name: error?.name,
      message: error?.message,
    });
    res.status(500).send('Webhook processing failed');
  }
}

async function handlePayUDisputeWebhook(req, res) {
  try {
    const payload = normalizePayUJsonPayload(req.body);
    const key = PAYU_MERCHANT_KEY.value();
    const salt = PAYU_MERCHANT_SALT.value();
    if (!key || !salt || String(payload.event || '').toLowerCase() !== 'dispute') {
      res.status(400).send('Unsupported dispute event');
      return;
    }
    await handlePayUDispute(payload, key, salt, req);
    res.status(200).send('OK');
  } catch (error) {
    console.error('PayU dispute webhook processing failed', {
      name: error?.name,
      message: error?.message,
    });
    res.status(500).send('Webhook processing failed');
  }
}

function normalizePayUJsonPayload(body) {
  if (body && typeof body === 'object' && !Array.isArray(body)) return body;
  if (typeof body === 'string') return JSON.parse(body);
  return {};
}

async function handlePayURefund(payload) {
  const refundId = String(payload.request_id || payload.token || '').trim();
  const orderId = String(payload.merchantTxnId || '').trim();
  const txnid = String(payload.mihpayid || '').trim();
  const status = String(payload.status || '').toLowerCase();
  const amountPaise = Math.round(Number(payload.amt || 0) * 100);
  if (!refundId || !orderId || !txnid || !['success', 'failure'].includes(status)) {
    throw apiError('PAYMENT_FAILED');
  }

  const refundRef = db.doc(`payu_refunds/${refundId}`);
  const orderRef = db.doc(`wallet_orders/${orderId}`);
  await db.runTransaction(async (transaction) => {
    const prior = await transaction.get(refundRef);
    if (prior.exists) return;

    const orderSnap = await transaction.get(orderRef);
    const order = orderSnap.exists ? orderSnap.data() : null;
    const walletRef = order && status === 'success' ?
      db.doc(`wallets/${order.accountId}`) : null;
    const walletSnap = walletRef ? await transaction.get(walletRef) : null;
    const event = {
      orderId,
      payuTransactionId: txnid,
      refundId,
      status,
      amountPaise,
      bankArn: String(payload.bank_arn || ''),
      bankReference: String(payload.bank_ref_num || ''),
      remark: String(payload.remark || ''),
      receivedAt: FieldValue.serverTimestamp(),
    };
    transaction.set(refundRef, event);

    if (status !== 'success' || !orderSnap.exists) return;

    const ledgerRef = walletRef.collection('ledger').doc(`payu_refund_${refundId}`);
    if (!walletSnap.exists) return;

    const balance = Number(walletSnap.get('balancePaise') || 0);
    transaction.set(walletRef, {
      balancePaise: balance - amountPaise,
      version: Number(walletSnap.get('version') || 0) + 1,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(ledgerRef, {
      type: 'debit', category: 'refund', amountPaise,
      balanceAfterPaise: balance - amountPaise,
      createdAt: FieldValue.serverTimestamp(),
      payuTransactionId: txnid, refundId,
    });
    transaction.update(orderRef, {
      status: amountPaise >= Number(order.amountPaise || 0) ? 'refunded' : 'partially_refunded',
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function handlePayUDispute(payload, key, salt, req) {
  const signature = String(
    req.get('X-PayU-Dispute-Webhook-Signature-V2') ||
    req.get('X-PayU-Dispute-Webhook-Signature-V1') || '',
  ).trim();
  if (signature) {
    const signedStatus = String(payload.cb_status || '').replace(/\s/g, '');
    const signed = [
      key, String(payload.txn_id || ''), String(payload.cb_amount || ''),
      String(payload.cb_id || ''), String(payload.cb_type || ''),
      signedStatus, salt,
    ].join('|');
    if (!timingSafeEqual(sha512(signed), signature)) {
      throw apiError('INVALID_WEBHOOK_HASH');
    }
  }

  const disputeId = String(payload.cb_id || '').trim();
  const txnid = String(payload.txn_id || '').trim();
  if (!disputeId || !txnid) throw apiError('PAYMENT_FAILED');
  await db.doc(`payu_disputes/${disputeId}`).set({
    payuTransactionId: txnid,
    merchantId: String(payload.mid || ''),
    status: String(payload.cb_status || ''),
    amountPaise: Math.round(Number(payload.cb_amount || 0) * 100),
    reason: String(payload.reason_code || ''),
    type: String(payload.cb_type || ''),
    dueDate: String(payload.due_date || ''),
    createdAt: String(payload.created_at || ''),
    updatedAt: String(payload.updated_at || ''),
    receivedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

function normalizePayUPayload(body) {
  if (typeof body === 'string') {
    return Object.fromEntries(new URLSearchParams(body));
  }
  return Object.fromEntries(
    Object.entries(body || {}).map(([key, value]) => [key, String(value ?? '')]),
  );
}

function verifyPayUResponseHash(payload, salt) {
  const additionalCharges = payload.additional_charges || payload.additionalCharges;
  const prefix = additionalCharges ? `${additionalCharges}|` : '';
  const value = [
    prefix + salt,
    payload.status,
    '', '', '', '', '',
    payload.udf5,
    payload.udf4,
    payload.udf3,
    payload.udf2,
    payload.udf1,
    payload.email,
    payload.firstname,
    payload.productinfo,
    payload.amount,
    payload.txnid,
    payload.key,
  ].join('|');
  return timingSafeEqual(sha512(value), payload.hash);
}

async function verifyPayUPayment(txnid, key, salt) {
  const command = 'verify_payment';
  const hash = sha512(`${key}|${command}|${txnid}|${salt}`);
  const response = await fetch(
    'https://info.payu.in/merchant/postservice.php?form=2',
    {
      method: 'POST',
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: new URLSearchParams({key, command, var1: txnid, hash}),
    },
  );
  if (!response.ok) throw new Error(`PayU verify returned HTTP ${response.status}`);
  const data = await response.json();
  const details = data.transaction_details?.[txnid] || {};
  if (Number(data.status) !== 1 && !details.status) {
    throw new Error('PayU verify did not return transaction details');
  }
  return details;
}

async function settlePayUOrder(orderId, txnid, amountPaise, status, payload, verified) {
  const orderRef = db.doc(`wallet_orders/${orderId}`);
  await db.runTransaction(async (transaction) => {
    const orderSnap = await transaction.get(orderRef);
    if (!orderSnap.exists) throw apiError('NOT_FOUND');
    const order = orderSnap.data();
    if (order.status === 'success' || order.status === 'failed') return;
    if (status === 'success') {
      if (Number(order.amountPaise) !== amountPaise) {
        throw new Error('PayU amount does not match the order');
      }
      const walletRef = db.doc(`wallets/${order.accountId}`);
      const ledgerRef = walletRef.collection('ledger').doc(`payu_${txnid}`);
      const walletSnap = await transaction.get(walletRef);
      const ledgerSnap = await transaction.get(ledgerRef);
      if (ledgerSnap.exists) return;
      const balance = Number(walletSnap.get('balancePaise') || 0);
      transaction.set(walletRef, {
        balancePaise: balance + amountPaise,
        minRechargeDone: true,
        version: Number(walletSnap.get('version') || 0) + 1,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(ledgerRef, {
        type: 'credit', category: 'topup', amountPaise,
        balanceAfterPaise: balance + amountPaise,
        createdAt: FieldValue.serverTimestamp(),
        payuTransactionId: txnid,
      });
      transaction.update(orderRef, {
        status: 'success', payuStatus: verified.status,
        payuId: payload.mihpayid || '', updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    if (status === 'failed') {
      transaction.update(orderRef, {
        status: 'failed', payuStatus: payload.status,
        payuId: payload.mihpayid || '', updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      transaction.update(orderRef, {
        status: 'pending', payuStatus: payload.status,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

function sha512(value) {
  return crypto.createHash('sha512').update(value).digest('hex');
}

function timingSafeEqual(expected, received) {
  const a = Buffer.from(String(expected));
  const b = Buffer.from(String(received));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
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
  const prices = await getLookupPrices();
  const pricePaise = type === 'rc' ? prices.rcPricePaise :
    type === 'phone' ? prices.phonePricePaise : 0;
  if (!pricePaise || !/^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$/.test(regNo)) throw apiError('INVALID_REG_NO');
  if (!wallet.minRechargeDone) throw apiError('RECHARGE_REQUIRED');
  if (wallet.balancePaise < pricePaise) throw apiError('INSUFFICIENT_BALANCE');

  // Fetch first so provider failures never consume wallet balance. The wallet
  // transaction below remains the server-side source of truth for charging.
  const providerResult = await lookupVehicleProvider(type, regNo);

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
    chargedPaise: pricePaise, createdAt: now, isDemo: false,
    rc: providerResult,
  } : {
    id: crypto.randomUUID(), type, regNo, regNoMasked: maskRegNo(regNo),
    chargedPaise: pricePaise, createdAt: now, isDemo: false,
    phone: providerResult,
  };
  res.json(result);
}

async function lookupVehicleProvider(type, regNo) {
  const endpointType = type === 'rc' ? 'rcplus' : 'rc2num';
  const key = type === 'rc' ? CSTUDIO_RCPLUS_KEY.value() : CSTUDIO_RC2NUM_KEY.value();
  if (!key) throw apiError('PROVIDER_UNAVAILABLE');

  const uri = new URL(CSTUDIO_API_BASE_URL);
  uri.search = new URLSearchParams({type: endpointType, key, query: regNo});
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetch(uri, {
      method: 'GET',
      headers: {'accept': 'application/json'},
      signal: controller.signal,
    });
    const text = await response.text();
    let payload;
    try {
      payload = JSON.parse(text);
    } catch (_) {
      throw apiError('PROVIDER_UNAVAILABLE');
    }
    if (!response.ok) throw apiError('PROVIDER_UNAVAILABLE');
    if (providerSaysNotFound(payload)) throw apiError('RECORD_NOT_FOUND');
    if (providerSaysFailure(payload)) throw apiError('PROVIDER_UNAVAILABLE');
    return type === 'rc' ? normalizeRcPayload(payload) : normalizePhonePayload(payload);
  } catch (error) {
    if (error?.code === 'RECORD_NOT_FOUND') throw error;
    console.error('Vehicle provider request failed', {
      type,
      name: error?.name,
      message: error?.message,
    });
    throw apiError('PROVIDER_UNAVAILABLE');
  } finally {
    clearTimeout(timeout);
  }
}

function providerData(payload) {
  if (!payload || typeof payload !== 'object') return {};
  if (payload.data && typeof payload.data === 'object') return payload.data;
  if (payload.result && typeof payload.result === 'object') return payload.result;
  return payload;
}

function firstValue(data, names) {
  for (const name of names) {
    const value = data[name];
    if (value !== undefined && value !== null && String(value).trim()) return String(value).trim();
  }
  return '';
}

function providerSaysNotFound(payload) {
  const text = JSON.stringify(payload).toLowerCase();
  return /not found|no record|no data|invalid vehicle/.test(text);
}

function providerSaysFailure(payload) {
  const status = String(payload?.status || payload?.success || '').toLowerCase();
  return ['false', 'failed', 'failure', 'error'].includes(status) ||
    Boolean(payload?.error && !payload?.data && !payload?.result);
}

function normalizeRcPayload(payload) {
  const data = providerData(payload);
  const ownerName = firstValue(data, ['ownerName', 'owner_name', 'owner', 'registeredOwner', 'registered_owner']);
  const maker = firstValue(data, ['maker', 'make', 'manufacturer', 'vehicleManufacturer', 'vehicle_manufacturer']);
  const model = firstValue(data, ['model', 'vehicleModel', 'vehicle_model']);
  if (!ownerName && !maker && !model) throw apiError('PROVIDER_UNAVAILABLE');
  const extra = {};
  for (const [key, value] of Object.entries(data)) {
    if (!['ownerName', 'owner_name', 'owner', 'registeredOwner', 'registered_owner', 'maker', 'make', 'manufacturer', 'vehicleManufacturer', 'vehicle_manufacturer', 'model', 'vehicleModel', 'vehicle_model'].includes(key) &&
        value !== null && value !== undefined && typeof value !== 'object') {
      extra[key] = String(value);
    }
  }
  return {ownerName: ownerName || 'Unavailable', maker: maker || 'Unavailable', model: model || 'Unavailable', extra};
}

function normalizePhonePayload(payload) {
  const data = providerData(payload);
  const phone = firstValue(data, ['phone', 'mobile', 'mobileNumber', 'mobile_number', 'ownerPhone', 'owner_phone']);
  if (!phone) throw apiError('RECORD_NOT_FOUND');
  return phone;
}

/**
 * Reads the published Firebase Remote Config template so pricing can change
 * without rebuilding the app or redeploying this function. The short cache
 * avoids an Admin API call on every lookup while still making changes visible
 * quickly.
 */
async function getLookupPrices() {
  const now = Date.now();
  if (lookupPricesCache && now - lookupPricesCachedAt < LOOKUP_PRICES_CACHE_MS) {
    return lookupPricesCache;
  }

  try {
    const template = await getRemoteConfig().getTemplate();
    const parameters = {
      ...(template.parameters || {}),
      ...Object.values(template.parameterGroups || {}).reduce(
        (all, group) => ({...all, ...(group.parameters || {})}),
        {},
      ),
    };
    const readPaise = (key, fallback) => {
      const value = parameters[key]?.defaultValue?.value;
      const parsed = Number(value);
      return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback;
    };
    const readRupeesAsPaise = (key, fallback) => {
      const value = parameters[key]?.defaultValue?.value;
      const parsed = Number(value);
      if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 1000000) return fallback;
      const paise = Math.round(parsed * 100);
      return Number.isSafeInteger(paise) ? paise : fallback;
    };
    lookupPricesCache = {
      rcPricePaise: readPaise('lookup_rc_price_paise', DEFAULT_LOOKUP_PRICES.rcPricePaise),
      phonePricePaise: readPaise('lookup_phone_price_paise', DEFAULT_LOOKUP_PRICES.phonePricePaise),
      minRechargePaise: readRupeesAsPaise(
        'onboarding_wallet_min_recharge',
        DEFAULT_LOOKUP_PRICES.minRechargePaise,
      ),
    };
  } catch (error) {
    console.error('Remote pricing config unavailable; using defaults', {
      name: error?.name,
      message: error?.message,
    });
    lookupPricesCache = DEFAULT_LOOKUP_PRICES;
  }
  lookupPricesCachedAt = now;
  return lookupPricesCache;
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
