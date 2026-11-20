import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/debug_log_service.dart';
import '../widgets/loopin_snackbar.dart';

class DebugConsolePage extends StatelessWidget {
  const DebugConsolePage({super.key});
  @override Widget build(BuildContext context) {
    final service = LoopinDebugLogService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Loopin diagnostics'), actions: [
        IconButton(tooltip: 'Copy logs', onPressed: () async {
          await Clipboard.setData(ClipboardData(text: service.exportText()));
          if (context.mounted) LoopinSnackBar.show(context, 'Logs copied to clipboard');
        }, icon: const Icon(Icons.copy_rounded)),
        IconButton(tooltip: 'Clear logs', onPressed: service.clear, icon: const Icon(Icons.delete_outline_rounded)),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: AnimatedBuilder(animation: service, builder: (context, _) {
            final logs = service.logs;
            if (logs.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No diagnostics yet. Retry the request and logs will appear here.', textAlign: TextAlign.center)));
            return ListView.separated(padding: const EdgeInsets.all(12), itemCount: logs.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, index) {
              final entry = logs[index];
              final color = entry.level == 'OK' ? Colors.greenAccent : entry.level == 'WARN' ? Colors.orangeAccent : entry.level == 'ERROR' ? Colors.redAccent : Colors.white70;
              final time = '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}';
              return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: SelectableText.rich(TextSpan(children: [
                TextSpan(text: '$time ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                TextSpan(text: '[${entry.level}] ', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
                TextSpan(text: entry.message, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.45)),
              ])));
            });
          }),
        ),
      ),
    );
  }
}