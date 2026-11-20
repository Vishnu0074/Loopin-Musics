import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';

class AchievementData {
  const AchievementData(this.title, this.subtitle, this.plays, this.hours, this.genre, this.streak, this.unlocked, this.next);
  final String title, subtitle, genre, next;
  final int plays, streak, unlocked;
  final double hours;
  factory AchievementData.fromStats(Map<String, dynamic> s) {
    final plays = (s['total_plays'] as num?)?.toInt() ?? 0;
    final hours = (s['total_played_hours'] as num?)?.toDouble() ?? 0;
    final streak = (s['listening_streak_days'] as num?)?.toInt() ?? 0;
    final raw = s['top_genre']?.toString().trim() ?? '';
    final genre = raw.isEmpty ? 'Discovering' : raw;
    final title = plays >= 10000 ? 'LEGENDARY LISTENER' : plays >= 5000 ? 'LOOPIN ICON' : plays >= 1000 ? 'THE MELODYHEAD' : plays >= 500 ? 'MUSIC ENTHUSIAST' : plays >= 100 ? 'RHYTHM SEEKER' : streak >= 7 ? 'DAILY GROOVE' : genre != 'Discovering' ? '${genre.toUpperCase()} LOVER' : 'FUTURE HEADLINER';
    final subtitle = plays >= 100 ? 'Every play adds another note to your story.' : streak >= 7 ? '$streak days of keeping the music alive.' : genre != 'Discovering' ? 'Your top genre is $genre.' : 'Your music identity starts here.';
    const milestones = [1, 100, 500, 1000, 5000, 10000];
    final unlocked = milestones.where((m) => plays >= m).length;
    final next = milestones.where((m) => plays < m).firstOrNull;
    return AchievementData(title, subtitle, plays, hours, genre, streak, unlocked, next == null ? 'All milestones reached' : '$next plays');
  }
}

class AchievementSection extends StatefulWidget {
  const AchievementSection({super.key});
  @override
  State<AchievementSection> createState() => _AchievementSectionState();
}
class _AchievementSectionState extends State<AchievementSection> {
  late Future<AchievementData> future;
  @override
  void initState() { super.initState(); future = _load(); }
  Future<AchievementData> _load() async => AchievementData.fromStats(await PlaylistService().stats());
  Future<void> _refresh() async { setState(() => future = _load()); await future; }
  @override
  Widget build(BuildContext context) => FutureBuilder<AchievementData>(future: future, builder: (context, snap) {
    if (snap.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(22), child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))));
    if (!snap.hasData) return _panel(Row(children: [const Expanded(child: Text('Achievements are temporarily unavailable.', style: TextStyle(color: AppColors.muted, fontSize: 12))), IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]));
    final d = snap.data!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('YOUR ACHIEVEMENTS', style: TextStyle(color: AppColors.accent, fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5), const Text('Your music has a story.', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const SizedBox(height: 12),
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFFFF4DB8), Color(0xFF741CFF)]), boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: .2), blurRadius: 16)]), child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 28)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(d.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ]),
        const SizedBox(height: 17),
        Row(children: [_stat(d.plays.toString(), 'PLAYS'), _stat(_hours(d.hours), 'LISTENING'), _stat(d.genre, 'TOP GENRE'), _stat('${d.streak}d', 'STREAK')]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Text('${d.unlocked} milestones unlocked · Next: ${d.next}', style: const TextStyle(color: AppColors.muted, fontSize: 10))),
          FilledButton.tonalIcon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AchievementsPage(data: d))), icon: const Icon(Icons.ios_share_rounded, size: 15), label: const Text('Share'), style: FilledButton.styleFrom(foregroundColor: AppColors.accent, backgroundColor: AppColors.accent.withValues(alpha: .12), visualDensity: VisualDensity.compact)),
        ]),
      ])),
    ]);
  });
}

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key, required this.data});
  final AchievementData data;
  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}
class _AchievementsPageState extends State<AchievementsPage> {
  final key = GlobalKey();
  bool sharing = false;
  Future<void> _share() async {
    if (sharing) return;
    setState(() => sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Achievement card is not ready.');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Could not render PNG.');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/loopin-achievement.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')], text: 'My Loopin music identity: ${widget.data.title}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share achievement: $e')));
    } finally { if (mounted) setState(() => sharing = false); }
  }
  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Scaffold(appBar: AppBar(title: const Text('Achievements')), body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
      Center(child: FittedBox(fit: BoxFit.scaleDown, child: RepaintBoundary(key: key, child: _ShareCard(data: d)))), const SizedBox(height: 18),
      FilledButton.icon(onPressed: sharing ? null : _share, icon: sharing ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share_rounded), label: Text(sharing ? 'Preparing image…' : 'Share achievement as PNG'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
      const SizedBox(height: 26), const Text('PLAY MILESTONES', style: TextStyle(color: AppColors.accent, fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w800)), const SizedBox(height: 12),
      for (final m in const [1, 100, 500, 1000, 5000, 10000]) _milestone(m, d.plays >= m),
    ]));
  }
  Widget _milestone(int plays, bool unlocked) {
    final label = switch (plays) { 1 => 'First note', 100 => 'Rhythm seeker', 500 => 'Music enthusiast', 1000 => 'The Melodyhead', 5000 => 'Loopin icon', _ => 'Legendary listener' };
    return Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: unlocked ? AppColors.accent.withValues(alpha: .28) : Colors.white10)), child: Row(children: [
      Icon(unlocked ? Icons.workspace_premium_rounded : Icons.lock_outline_rounded, color: unlocked ? AppColors.accent : AppColors.muted), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)), Text('$plays total plays', style: const TextStyle(color: AppColors.muted, fontSize: 11))])),
      if (unlocked) const Icon(Icons.check_circle_rounded, color: Color(0xFF6FCF97), size: 18),
    ]));
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.data});
  final AchievementData data;
  @override
  Widget build(BuildContext context) => SizedBox(width: 360, height: 540, child: ClipRRect(borderRadius: BorderRadius.circular(22), child: Stack(fit: StackFit.expand, children: [
    Image.asset('assets/images/Neon Rose-Gold Vinyl Music Trophy.png', width: 360, height: 540, fit: BoxFit.cover),
    const Positioned(top: 20, left: 22, child: Row(children: [Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 22), SizedBox(width: 7), Text('Loopin', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))])),
    const Positioned(top: 74, left: 0, right: 0, child: Icon(Icons.workspace_premium_rounded, color: Color(0xFFFF70CF), size: 48)),
    Positioned(top: 145, left: 18, right: 18, child: Column(children: [
      const Text('YOUR ACHIEVEMENT', style: TextStyle(color: AppColors.accent, fontSize: 10, letterSpacing: 2.2, fontWeight: FontWeight.w900)), const SizedBox(height: 9),
      Text(data.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 24, height: 1.05, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8), Text(data.subtitle, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ])),
    Positioned(left: 16, right: 16, bottom: 88, child: Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6), decoration: BoxDecoration(color: const Color(0xAA100817), borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.accent.withValues(alpha: .6))), child: Row(children: [
      _shareStat(Icons.play_circle_outline_rounded, data.plays.toString(), 'Total plays'), _shareStat(Icons.schedule_rounded, _hours(data.hours), 'Listening time'), _shareStat(Icons.music_note_rounded, data.genre, 'Top genre'), _shareStat(Icons.local_fire_department_rounded, '${data.streak}d', 'Streak'),
    ]))),
    const Positioned(left: 22, bottom: 25, child: Text('YOUR MUSIC. YOUR IDENTITY.', style: TextStyle(color: AppColors.accent, fontSize: 9, letterSpacing: 1.3, fontWeight: FontWeight.w800))),
    const Positioned(right: 22, bottom: 24, child: Text('LOOPIN', style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w900))),
  ])));
}
Widget _shareStat(IconData icon, String value, String label) => Expanded(child: Column(children: [Icon(icon, color: AppColors.accent, size: 19), const SizedBox(height: 6), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 8))]));


Widget _panel(Widget child) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: .06))), child: child);
Widget _stat(String value, String label) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 8, letterSpacing: .7))]));
String _hours(double value) { final mins = (value * 60).round(); if (mins < 60) return '${mins}m'; final h = mins ~/ 60; final m = mins % 60; return m == 0 ? '${h}h' : '${h}h ${m}m'; }
