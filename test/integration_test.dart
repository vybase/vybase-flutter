// Runs against a real Vybase API. Start one locally first:
//   ZYV_ADMIN_TOKEN=dev pnpm dev
// then: VYBASE_TEST_URL=http://localhost:8787 VYBASE_TEST_ADMIN=dev dart test
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:vybase/vybase.dart';

final url = Platform.environment['VYBASE_TEST_URL'];
final admin = Platform.environment['VYBASE_TEST_ADMIN'];

void main() {
  if (url == null || admin == null) {
    test('integration (skipped: set VYBASE_TEST_URL and VYBASE_TEST_ADMIN)', () {}, skip: true);
    return;
  }
  late String pk;
  final tag = Random().nextInt(1 << 30);

  setUpAll(() async {
    final r = await http.post(Uri.parse('$url/v1/system/projects'),
        headers: {'authorization': 'Bearer $admin', 'content-type': 'application/json'}, body: jsonEncode({'name': 'dart-sdk-test'}));
    expect(r.statusCode, 201);
    pk = (jsonDecode(r.body)['keys'] as Map)['publishable'] as String;
  });

  test('sign up, events, refresh rotation, update, sign out', () async {
    final zyv = Vybase(url: url!, key: pk);
    final events = <AuthEvent>[];
    final sub = zyv.auth.onAuthStateChange.listen((s) => events.add(s.event));

    final res = await zyv.auth.signUp(email: 'dart$tag@example.com', password: 'password-123', metadata: {'plan': 'free'});
    expect(res.session, isNotNull);
    expect(res.user.email, 'dart$tag@example.com');
    expect(res.user.metadata['plan'], 'free');
    expect((await zyv.auth.getUser()).id, res.user.id);

    final old = res.session!.refreshToken;
    final refreshed = await zyv.auth.refreshSession();
    expect(refreshed.refreshToken, isNot(old));

    final u = await zyv.auth.updateUser(metadata: {'name': 'Dart'});
    expect(u.metadata, {'plan': 'free', 'name': 'Dart'});

    await zyv.auth.signOut();
    expect(await zyv.auth.getSession(), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(events, [AuthEvent.signedIn, AuthEvent.tokenRefreshed, AuthEvent.userUpdated, AuthEvent.signedOut]);
    await sub.cancel();
  });

  test('errors carry stable codes', () async {
    final zyv = Vybase(url: url!, key: pk);
    await zyv.auth.signUp(email: 'dup$tag@example.com', password: 'password-123');
    await expectLater(
      zyv.auth.signUp(email: 'dup$tag@example.com', password: 'password-123'),
      throwsA(isA<VybaseException>().having((e) => e.code, 'code', 'email_taken').having((e) => e.status, 'status', 409)),
    );
    await expectLater(
      Vybase(url: url!, key: pk).auth.signInWithPassword(email: 'dup$tag@example.com', password: 'wrong-pass'),
      throwsA(isA<VybaseException>().having((e) => e.code, 'code', 'invalid_credentials')),
    );
    await expectLater(Vybase(url: url!, key: 'pk_nope').auth.getSettings(), throwsA(isA<VybaseException>().having((e) => e.code, 'code', 'invalid_api_key')));
  });

  test('settings and phone sign-in switch', () async {
    final zyv = Vybase(url: url!, key: pk);
    final s = await zyv.auth.getSettings();
    expect(s.emailPassword, isTrue);
    expect(s.sms, isFalse);
    await expectLater(zyv.auth.signInWithOtp(phone: '+923001234567'), throwsA(isA<VybaseException>().having((e) => e.code, 'code', 'provider_disabled')));
  });

  test('OAuth URL carries PKCE and the publishable key', () async {
    final zyv = Vybase(url: url!, key: pk);
    final u = await zyv.auth.getOAuthSignInUrl(provider: OAuthProvider.google, redirectTo: 'com.example.app://callback');
    expect(u.path, '/v1/auth/authorize');
    expect(u.queryParameters['provider'], 'google');
    expect(u.queryParameters['apikey'], pk);
    expect(u.queryParameters['code_challenge'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
  });

  test('session survives a restart through storage', () async {
    final storage = MemoryStorage();
    final a = Vybase(url: url!, key: pk, storage: storage);
    final res = await a.auth.signUp(email: 'persist$tag@example.com', password: 'password-123');
    final b = Vybase(url: url!, key: pk, storage: storage);
    expect((await b.auth.getSession())?.user.id, res.user.id);
  });
}
