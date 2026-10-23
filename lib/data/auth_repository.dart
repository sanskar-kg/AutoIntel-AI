import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:truecaller_sdk/truecaller_sdk.dart';

import 'models.dart';
import 'backend.dart';

/// Real authentication client. The Truecaller authorization code is exchanged
/// only by the configured backend; the app never receives or stores a provider
/// access token.
class ProductionAuthRepository implements AuthRepository {
  ProductionAuthRepository(this._prefs)
    : _secureStorage = const FlutterSecureStorage();

  static const _cachedAccountKey = 'auth.cached_account.v1';
  // Production is the default so normal Play Store builds do not require a
  // dart-define. Staging/local builds can still override this value.
  static const _apiBaseUrl = String.fromEnvironment(
    'AUTH_API_BASE_URL',
    defaultValue:
        'https://asia-south1-autointel-ai-app.cloudfunctions.net/authApi',
  );
  static const _sessionTokenKey = 'auth.session_token';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;
  StreamSubscription<TcSdkCallback>? _truecallerSubscription;

  @override
  Future<Account?> restore() async {
    final cached = _prefs.getString(_cachedAccountKey);
    if (cached == null) return null;
    try {
      return _accountFromJson(
        Map<String, Object?>.from(jsonDecode(cached) as Map),
      );
    } catch (_) {
      await _prefs.remove(_cachedAccountKey);
      return null;
    }
  }

  @override
  Future<Account> signIn() async {
    final account = await _signInWithTruecaller();
    await _cache(account);
    return account;
  }

  Future<Account> _signInWithTruecaller() async {
    if (_apiBaseUrl.isEmpty) {
      throw const AuthException('AUTH_API_BASE_URL is not configured');
    }

    _ignorePending(
      TcSdk.initializeSDK(sdkOption: TcSdkOptions.OPTION_VERIFY_ONLY_TC_USERS),
    );
    if (!await TcSdk.isOAuthFlowUsable) {
      throw const AuthException('Truecaller is not available on this device');
    }

    final state = _randomToken();
    final verifier = await TcSdk.generateRandomCodeVerifier;
    final challenge = await TcSdk.generateCodeChallenge(verifier);
    if (challenge == null) {
      throw const AuthException('Truecaller device does not support PKCE');
    }

    _ignorePending(TcSdk.setOAuthState(state));
    _ignorePending(TcSdk.setOAuthScopes(['profile', 'phone', 'openid']));
    _ignorePending(TcSdk.setCodeChallenge(challenge));

    final callback = Completer<TcSdkCallback>();
    await _truecallerSubscription?.cancel();
    _truecallerSubscription = TcSdk.streamCallbackData.listen((event) {
      if (!callback.isCompleted) callback.complete(event);
    });
    try {
      unawaited(
        TcSdk.getAuthorizationCode.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            if (!callback.isCompleted) {
              callback.completeError(error, stackTrace);
            }
          },
        ),
      );
      final result = await callback.future.timeout(const Duration(minutes: 2));
      if (result.result != TcSdkCallbackResult.success ||
          result.tcOAuthData == null) {
        throw AuthException(
          result.error?.message ?? 'Truecaller sign-in failed',
        );
      }
      final oauth = result.tcOAuthData!;
      if (oauth.state != state) {
        throw const AuthException('Truecaller state validation failed');
      }

      final response = await http.post(
        Uri.parse('$_apiBaseUrl/v1/auth/truecaller'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'authorizationCode': oauth.authorizationCode,
          'codeVerifier': verifier,
          'state': oauth.state,
          'scopesGranted': oauth.scopesGranted,
        }),
      );
      if (response.statusCode != 200) {
        throw AuthException('Authentication server rejected the sign-in');
      }
      final payload = Map<String, Object?>.from(
        jsonDecode(response.body) as Map,
      );
      final token = payload['sessionToken'] as String?;
      final profile = Map<String, Object?>.from(payload['account'] as Map);
      if (token == null || token.isEmpty) {
        throw const AuthException('Authentication server returned no session');
      }
      await _secureStorage.write(key: _sessionTokenKey, value: token);
      return _accountFromJson(profile);
    } finally {
      await _truecallerSubscription?.cancel();
      _truecallerSubscription = null;
    }
  }

  void _ignorePending(Future<dynamic> operation) {
    // truecaller_sdk 1.1.0's Android channel executes these methods but does
    // not send MethodChannel success results, so awaiting them never finishes.
    unawaited(operation.then<void>((_) {}, onError: (_, _) {}));
  }

  @override
  Future<Account> signInAnonymously() async {
    Account account;
    try {
      final firebaseUser = await _firebaseAnonymousUser();
      account = Account(
        id: 'firebase:${firebaseUser.uid}',
        name: 'Temporary account',
        provider: 'firebase_anonymous',
        isTemporary: true,
      );
      final idToken = await firebaseUser.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('Temporary authentication token missing');
      }
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/v1/auth/anonymous'),
        headers: {'Authorization': 'Bearer $idToken'},
      );
      if (response.statusCode != 200) {
        throw const AuthException('Temporary account could not be created');
      }
      final payload = Map<String, Object?>.from(
        jsonDecode(response.body) as Map,
      );
      await _secureStorage.write(
        key: _sessionTokenKey,
        value: payload['sessionToken'] as String,
      );
    } catch (_) {
      // Allows local development and widget tests before Firebase is configured.
      account = Account(
        id: 'local-anonymous:${_randomToken()}',
        name: 'Temporary account',
        provider: 'local_anonymous',
        isTemporary: true,
      );
    }
    await _cache(account);
    return account;
  }

  @override
  Future<String?> sessionToken() => _secureStorage.read(key: _sessionTokenKey);

  Future<User> _firebaseAnonymousUser() async {
    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null) return current;
    return (await auth.signInAnonymously()).user!;
  }

  @override
  Future<void> signOut() async {
    await _secureStorage.delete(key: _sessionTokenKey);
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Firebase is optional until the project configuration is supplied.
    }
    await _prefs.remove(_cachedAccountKey);
  }

  Future<void> _cache(Account account) => _prefs
      .setString(
        _cachedAccountKey,
        jsonEncode({
          'id': account.id,
          'name': account.name,
          'email': account.email,
          'phone': account.phone,
          'provider': account.provider,
          'isTemporary': account.isTemporary,
          'isPhoneVerified': account.isPhoneVerified,
        }),
      )
      .then((_) {});

  static Account _accountFromJson(Map<String, Object?> json) => Account(
    id: json['id']! as String,
    name: (json['name'] as String?) ?? 'AutoIntel user',
    email: (json['email'] as String?) ?? '',
    phone: (json['phone'] as String?) ?? '',
    provider: (json['provider'] as String?) ?? 'truecaller',
    isTemporary: (json['isTemporary'] as bool?) ?? false,
    isPhoneVerified: (json['isPhoneVerified'] as bool?) ?? false,
  );

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
