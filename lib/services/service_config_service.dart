import 'auth_service.dart';

class ServiceConfig {
  final bool enabled;
  final String label;
  final String message;

  const ServiceConfig({
    required this.enabled,
    required this.label,
    required this.message,
  });

  factory ServiceConfig.fromJson(Map<String, dynamic> json) => ServiceConfig(
    enabled: json['enabled'] != false,
    label: json['label']?.toString() ?? '',
    message: json['message']?.toString() ?? '',
  );
}

class ServiceConfigService {
  static final ServiceConfigService _i = ServiceConfigService._();
  factory ServiceConfigService() => _i;
  ServiceConfigService._();

  final _api = AuthService();
  Map<String, ServiceConfig>? _cache;
  DateTime? _at;

  Future<ServiceConfig?> get(String key, {bool forceRefresh = false}) async {
    try {
      if (forceRefresh || _cache == null || _at == null ||
          DateTime.now().difference(_at!) > const Duration(seconds: 30)) {
        final d = await _api.get('/catalog/config/', authenticated: false).timeout(
          const Duration(seconds: 3),
        );
        final raw = Map<String, dynamic>.from(d['services'] ?? {});
        _cache = {
          for (final entry in raw.entries)
            entry.key: ServiceConfig.fromJson(Map<String, dynamic>.from(entry.value as Map)),
        };
        _at = DateTime.now();
      }
      return _cache?[key];
    } catch (_) {
      // Fail open so a temporary config outage does not unnecessarily block playback.
      return null;
    }
  }

  /// Read the last known flag without waiting for a network request.
  /// Before the first response, default to enabled so playback stays responsive.
  bool enabledCached(String key) => _cache?[key]?.enabled ?? true;

  /// Refresh service flags in the background; a failure retains the cache.
  Future<void> refresh() async {
    await get('streaming', forceRefresh: _cache == null);
  }

  Future<bool> enabled(String key, {bool forceRefresh = false}) async {
    final config = await get(key, forceRefresh: forceRefresh);
    return config?.enabled ?? true;
  }

  Future<String> message(String key) async {
    final config = await get(key);
    return (config?.message.trim().isNotEmpty == true)
        ? config!.message
        : 'This feature is temporarily unavailable.';
  }

  void clear() {
    _cache = null;
    _at = null;
  }
}