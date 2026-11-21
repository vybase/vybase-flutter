class VybaseUser {
  VybaseUser({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.phone,
    required this.phoneVerified,
    required this.metadata,
    required this.providers,
    required this.banned,
    required this.createdAt,
    required this.lastSignInAt,
  });

  final String id;
  final String? email;
  final bool emailVerified;
  final String? phone;
  final bool phoneVerified;
  final Map<String, dynamic> metadata;
  final List<String> providers;
  final bool banned;
  final DateTime createdAt;
  final DateTime? lastSignInAt;

  factory VybaseUser.fromJson(Map<String, dynamic> j) => VybaseUser(
        id: j['id'] as String,
        email: j['email'] as String?,
        emailVerified: j['email_verified'] as bool? ?? false,
        phone: j['phone'] as String?,
        phoneVerified: j['phone_verified'] as bool? ?? false,
        metadata: Map<String, dynamic>.from(j['metadata'] as Map? ?? const {}),
        providers: List<String>.from(j['providers'] as List? ?? const []),
        banned: j['banned'] as bool? ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
        lastSignInAt: j['last_sign_in_at'] == null ? null : DateTime.parse(j['last_sign_in_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'email_verified': emailVerified,
        'phone': phone,
        'phone_verified': phoneVerified,
        'metadata': metadata,
        'providers': providers,
        'banned': banned,
        'created_at': createdAt.toIso8601String(),
        'last_sign_in_at': lastSignInAt?.toIso8601String(),
      };
}

class VybaseSession {
  VybaseSession({required this.accessToken, required this.refreshToken, required this.expiresAt, required this.user});

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final VybaseUser user;

  bool get isExpiringSoon => expiresAt.difference(DateTime.now()) < const Duration(seconds: 60);

  VybaseSession copyWith({VybaseUser? user}) =>
      VybaseSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt, user: user ?? this.user);

  factory VybaseSession.fromApi(Map<String, dynamic> session, Map<String, dynamic> user) => VybaseSession(
        accessToken: session['access_token'] as String,
        refreshToken: session['refresh_token'] as String,
        expiresAt: DateTime.now().add(Duration(seconds: (session['expires_in'] as num).toInt())),
        user: VybaseUser.fromJson(user),
      );

  factory VybaseSession.fromJson(Map<String, dynamic> j) => VybaseSession(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        user: VybaseUser.fromJson(Map<String, dynamic>.from(j['user'] as Map)),
      );

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'user': user.toJson(),
      };
}

class AuthResponse {
  AuthResponse({required this.user, this.session, this.verificationRequired = false, this.isRecovery = false});

  final VybaseUser user;

  /// Null when the project requires email confirmation and the user hasn't confirmed yet.
  final VybaseSession? session;
  final bool verificationRequired;

  /// True when this sign-in came from a password-reset link: ask for a new password next.
  final bool isRecovery;
}

class AuthSettings {
  AuthSettings(this.raw);
  final Map<String, dynamic> raw;
  bool get emailPassword => raw['email_password'] == true;
  bool get emailOtp => raw['email_otp'] == true;
  bool get google => raw['google'] == true;
  List<String> get googleClientIds => List<String>.from(raw['google_client_ids'] as List? ?? const []);
  bool get sms => raw['sms'] == true;
  bool get whatsapp => raw['whatsapp'] == true;
  bool get zyvraon => raw['zyvraon'] == true;
}

enum AuthEvent { signedIn, signedOut, tokenRefreshed, userUpdated, passwordRecovery }

class AuthState {
  AuthState(this.event, this.session);
  final AuthEvent event;
  final VybaseSession? session;
}

enum OtpChannel { auto, sms, whatsapp }

enum OAuthProvider { google, zyvraon }
