import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'client.dart';
import 'errors.dart';
import 'models.dart';
import 'storage.dart';

class VybaseAuth {
  VybaseAuth(this._client, this._storage) : _storageKey = 'zyv-auth-${_client.key.substring(0, min(12, _client.key.length))}';

  final Vybase _client;
  final VybaseStorage _storage;
  final String _storageKey;
  final _events = StreamController<AuthState>.broadcast();
  Future<VybaseSession>? _refreshing;
  VybaseSession? _cached;

  String get _verifierKey => '$_storageKey-pkce';

  /// Sign-in / sign-out / refresh events.
  Stream<AuthState> get onAuthStateChange => _events.stream;

  /// The session loaded by the last call, without touching storage or the network.
  VybaseSession? get currentSession => _cached;
  VybaseUser? get currentUser => _cached?.user;

  // ---- internals ---------------------------------------------------------------------------

  Future<VybaseSession?> _load() async {
    if (_cached != null) return _cached;
    final raw = await _storage.read(_storageKey);
    if (raw == null) return null;
    try {
      return _cached = VybaseSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<VybaseSession> _save(VybaseSession s, AuthEvent event) async {
    _cached = s;
    await _storage.write(_storageKey, jsonEncode(s.toJson()));
    _events.add(AuthState(event, s));
    return s;
  }

  Future<void> _clear() async {
    _cached = null;
    await _storage.delete(_storageKey);
    _events.add(AuthState(AuthEvent.signedOut, null));
  }

  Future<AuthResponse> _toAuth(Map<String, dynamic>? r, [AuthEvent event = AuthEvent.signedIn]) async {
    final user = Map<String, dynamic>.from(r!['user'] as Map);
    final session = r['session'] as Map<String, dynamic>?;
    final recovery = r['type'] == 'recovery';
    VybaseSession? s;
    if (session != null) s = await _save(VybaseSession.fromApi(session, user), recovery ? AuthEvent.passwordRecovery : event);
    return AuthResponse(
      user: VybaseUser.fromJson(user),
      session: s,
      verificationRequired: r['verification_required'] == true,
      isRecovery: recovery,
    );
  }

  Future<String> _token() async {
    final s = await getSession();
    if (s == null) throw VybaseException('no_session', 'Not signed in.', status: 401);
    return s.accessToken;
  }

  // ---- sign up / sign in -------------------------------------------------------------------

  Future<AuthSettings> getSettings() async => AuthSettings((await _client.request('GET', '/v1/auth/settings'))!);

  Future<AuthResponse> signUp({required String email, required String password, Map<String, dynamic>? metadata, String? redirectTo}) async =>
      _toAuth(await _client.request('POST', '/v1/auth/signup', body: {
        'email': email,
        'password': password,
        if (metadata != null) 'metadata': metadata,
        if (redirectTo != null) 'redirect_to': redirectTo,
      }));

  Future<AuthResponse> signInWithPassword({required String email, required String password}) async =>
      _toAuth(await _client.request('POST', '/v1/auth/login', body: {'email': email, 'password': password}));

  /// Sends a 6-digit code to [email], or to [phone] (international format, e.g. +923001234567) by SMS or WhatsApp.
  Future<void> signInWithOtp({String? email, String? phone, OtpChannel channel = OtpChannel.auto}) async {
    if ((email == null) == (phone == null)) throw ArgumentError('Pass exactly one of email or phone.');
    await _client.request('POST', '/v1/auth/otp/send', body: email != null ? {'email': email} : {'phone': phone, 'channel': channel.name});
  }

  Future<AuthResponse> verifyOtp({String? email, String? phone, required String code}) async {
    if ((email == null) == (phone == null)) throw ArgumentError('Pass exactly one of email or phone.');
    return _toAuth(await _client.request('POST', '/v1/auth/otp/verify', body: {if (email != null) 'email': email, if (phone != null) 'phone': phone, 'code': code}));
  }

  /// Native Google sign-in: pass the ID token from `google_sign_in` (`googleAuth.idToken`).
  Future<AuthResponse> signInWithIdToken({required String idToken, String? nonce}) async =>
      _toAuth(await _client.request('POST', '/v1/auth/idtoken', body: {'provider': 'google', 'id_token': idToken, if (nonce != null) 'nonce': nonce}));

  /// Returns the URL to open in a browser (e.g. `flutter_web_auth_2`). When the browser returns to
  /// [redirectTo] with `?code=…`, call [exchangeCodeForSession].
  Future<Uri> getOAuthSignInUrl({required OAuthProvider provider, required String redirectTo}) async {
    final rnd = Random.secure();
    final verifier = base64Url.encode(List<int>.generate(48, (_) => rnd.nextInt(256))).replaceAll('=', '');
    final challenge = base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    await _storage.write(_verifierKey, verifier);
    return Uri.parse('${_client.url}/v1/auth/authorize').replace(queryParameters: {
      'provider': provider.name,
      'redirect_to': redirectTo,
      'code_challenge': challenge,
      'apikey': _client.key,
    });
  }

  /// Finishes OAuth, email-confirmation and password-reset links.
  Future<AuthResponse> exchangeCodeForSession(String code) async {
    final verifier = await _storage.read(_verifierKey);
    final r = await _client.request('POST', '/v1/auth/token', body: {'code': code, if (verifier != null) 'code_verifier': verifier});
    await _storage.delete(_verifierKey);
    return _toAuth(r);
  }

  Future<void> resendVerification({required String email, String? redirectTo}) async =>
      _client.request('POST', '/v1/auth/verify/resend', body: {'email': email, if (redirectTo != null) 'redirect_to': redirectTo});

  Future<void> resetPasswordForEmail({required String email, String? redirectTo}) async =>
      _client.request('POST', '/v1/auth/recover', body: {'email': email, if (redirectTo != null) 'redirect_to': redirectTo});

  // ---- session -----------------------------------------------------------------------------

  /// The stored session, refreshed first when the access token is about to expire.
  Future<VybaseSession?> getSession() async {
    final s = await _load();
    if (s == null) return null;
    if (s.isExpiringSoon) {
      try {
        return await refreshSession();
      } on VybaseException catch (e) {
        if (e.status == 0) return s; // offline: keep it, try again later
        rethrow;
      }
    }
    return s;
  }

  Future<VybaseSession> refreshSession() {
    // A refresh token is single-use: never run two refreshes at once.
    return _refreshing ??= () async {
      try {
        final s = await _load();
        if (s == null) throw VybaseException('no_session', 'Not signed in.', status: 401);
        try {
          final r = (await _client.request('POST', '/v1/auth/refresh', body: {'refresh_token': s.refreshToken}))!;
          return await _save(VybaseSession.fromApi(r['session'] as Map<String, dynamic>, Map<String, dynamic>.from(r['user'] as Map)), AuthEvent.tokenRefreshed);
        } on VybaseException catch (e) {
          if (e.code == 'refresh_conflict') {
            // Another isolate/device instance refreshed a moment ago: reload the newer tokens from storage.
            for (final wait in [Duration.zero, const Duration(milliseconds: 800)]) {
              await Future<void>.delayed(wait);
              _cached = null;
              final latest = await _load();
              if (latest != null && latest.refreshToken != s.refreshToken) return latest;
            }
          }
          if (e.status == 401) await _clear();
          rethrow;
        }
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<VybaseUser> getUser() async {
    final r = await _client.request('GET', '/v1/auth/user', token: await _token());
    return VybaseUser.fromJson(r!['user'] as Map<String, dynamic>);
  }

  Future<VybaseUser> updateUser({Map<String, dynamic>? metadata, String? password}) async {
    final r = await _client.request('PATCH', '/v1/auth/user',
        body: {if (metadata != null) 'metadata': metadata, if (password != null) 'password': password}, token: await _token());
    final user = VybaseUser.fromJson(r!['user'] as Map<String, dynamic>);
    final s = await _load();
    if (s != null) await _save(s.copyWith(user: user), AuthEvent.userUpdated);
    return user;
  }

  /// [global] signs out every device.
  Future<void> signOut({bool global = false}) async {
    final s = await _load();
    if (s != null) {
      try {
        await _client.request('POST', '/v1/auth/logout${global ? '?scope=global' : ''}', token: s.accessToken);
      } on VybaseException catch (e) {
        if (e.status != 401) {
          await _clear();
          rethrow;
        }
      }
    }
    await _clear();
  }

  void dispose() => _events.close();
}
