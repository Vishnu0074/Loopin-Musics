import 'dart:collection';
import 'package:flutter/foundation.dart';

class LoopinDebugLog {
  final DateTime time; final String level; final String message;
  const LoopinDebugLog({required this.time, required this.level, required this.message});
}

class LoopinDebugLogService extends ChangeNotifier {
  LoopinDebugLogService._(); static final instance = LoopinDebugLogService._();
  static const _maxEntries = 300; final List<LoopinDebugLog> _logs = [];
  UnmodifiableListView<LoopinDebugLog> get logs => UnmodifiableListView(_logs);
  void info(String message) => _add('INFO', message);
  void success(String message) => _add('OK', message);
  void warning(String message) => _add('WARN', message);
  void error(String message) => _add('ERROR', message);
  void _add(String level, String message) {
    _logs.add(LoopinDebugLog(time: DateTime.now(), level: level, message: message));
    if (_logs.length > _maxEntries) _logs.removeRange(0, _logs.length - _maxEntries);
    debugPrint('[Loopin][$level] $message'); notifyListeners();
  }
  void clear() { _logs.clear(); notifyListeners(); }
  String exportText() => _logs.map((e) => '[${e.time.toIso8601String()}] [${e.level}] ${e.message}').join('\n');
}