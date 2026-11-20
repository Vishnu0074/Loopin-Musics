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

/// Local feature flags for the standalone V2 client. A backend is not required
/// for discovery, playback, lyrics, local library or recommendations.
class ServiceConfigService {
  static final ServiceConfigService _instance = ServiceConfigService._();
  factory ServiceConfigService() => _instance;
  ServiceConfigService._();

  static const _defaults = <String, ServiceConfig>{
    'streaming': ServiceConfig(enabled: true, label: 'Music streaming', message: ''),
    'search': ServiceConfig(enabled: true, label: 'Search', message: ''),
    'recommendations': ServiceConfig(enabled: true, label: 'Smart recommendations', message: ''),
    'high_quality_audio': ServiceConfig(enabled: true, label: 'High quality audio', message: ''),
    'listening_sync': ServiceConfig(enabled: true, label: 'Local listening history', message: ''),
  };

  Future<ServiceConfig?> get(String key, {bool forceRefresh = false}) async =>
      _defaults[key];

  bool enabledCached(String key) => _defaults[key]?.enabled ?? true;

  Future<void> refresh() async {}

  Future<bool> enabled(String key, {bool forceRefresh = false}) async =>
      enabledCached(key);

  Future<String> message(String key) async =>
      _defaults[key]?.message.isNotEmpty == true
          ? _defaults[key]!.message
          : 'This feature is temporarily unavailable.';

  void clear() {}
}
