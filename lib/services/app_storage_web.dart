import 'package:web/web.dart' as web;

/// Browser storage adapter using package:web. localStorage is accessed defensively
/// because privacy modes and embedded browsers can deny storage access.
/// The in-memory fallback keeps the app usable for the lifetime of the tab in that case.
class AppStorage {
  AppStorage();

  static final Map<String, String> _memory = <String, String>{};

  Future<String?> read({required String key}) async {
    try {
      final value = web.window.localStorage.getItem(key);
      if (value != null) return value;
    } catch (_) {
      // Continue with the per-tab fallback.
    }
    return _memory[key];
  }

  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      await delete(key: key);
      return;
    }
    _memory[key] = value;
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {
      // Memory fallback is intentionally retained when browser storage is blocked.
    }
  }

  Future<void> delete({required String key}) async {
    _memory.remove(key);
    try {
      web.window.localStorage.removeItem(key);
    } catch (_) {
      // Nothing else to clear when persistent storage is unavailable.
    }
  }
}
