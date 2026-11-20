import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Platform-neutral key/value storage used by authentication and preferences.
/// Native platforms retain encrypted storage through flutter_secure_storage.
class AppStorage {
  AppStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<String?> read({required String key}) => _storage.read(key: key);

  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<void> delete({required String key}) => _storage.delete(key: key);
}
