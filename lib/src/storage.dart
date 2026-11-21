/// Where the session is kept between app launches.
///
/// The default [MemoryStorage] forgets the session when the app closes. In Flutter, persist it with
/// `flutter_secure_storage` (recommended) or `shared_preferences`:
///
/// ```dart
/// class SecureStorage implements VybaseStorage {
///   final _s = const FlutterSecureStorage();
///   @override Future<String?> read(String key) => _s.read(key: key);
///   @override Future<void> write(String key, String value) => _s.write(key: key, value: value);
///   @override Future<void> delete(String key) => _s.delete(key: key);
/// }
/// ```
abstract class VybaseStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryStorage implements VybaseStorage {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}
