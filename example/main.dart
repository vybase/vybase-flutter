import 'package:vybase/vybase.dart';

Future<void> main() async {
  final zyv = Vybase(url: 'https://auth.zyvraone.site', key: 'pk_your_publishable_key');

  zyv.auth.onAuthStateChange.listen((state) => print('auth: ${state.event} ${state.session?.user.email}'));

  try {
    // WhatsApp code sign-in
    await zyv.auth.signInWithOtp(phone: '+923001234567', channel: OtpChannel.whatsapp);
    final res = await zyv.auth.verifyOtp(phone: '+923001234567', code: '123456');
    print('Signed in as ${res.user.phone}');
  } on VybaseException catch (e) {
    print('Failed: ${e.code} — ${e.message}');
  }
}
