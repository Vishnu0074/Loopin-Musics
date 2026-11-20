import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/loopin_snackbar.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  final _api = AuthService();
  late final TabController _tabs;
  List<Map<String, dynamic>> services = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> listening = [];
  int totalUsers = 0, maxUsers = 0, totalListening = 0, page = 1;
  String filter = 'history';
  bool loading = true, loadingPage = false, hasNext = false;

  @override void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); _load(); }
  @override void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final result = await Future.wait([
        _api.get('/catalog/admin/services/'),
        _api.get('/auth/admin/users/?page=1&page_size=25'),
        _api.get('/listening/admin/listening/?type=$filter&page=1&page_size=25'),
      ]);
      if (!mounted) return;
      setState(() {
        services = List<Map<String, dynamic>>.from((result[0]['services'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
        users = List<Map<String, dynamic>>.from((result[1]['users'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
        totalUsers = result[1]['total_users'] ?? 0; maxUsers = result[1]['max_users'] ?? 0;
        listening = List<Map<String, dynamic>>.from((result[2]['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
        totalListening = result[2]['total'] ?? 0; hasNext = result[2]['has_next'] == true; page = 1; loading = false;
      });
    } catch (e) { if (mounted) { setState(() => loading = false); LoopinSnackBar.show(context, e.toString()); } }
  }

  Future<void> _setUserActive(Map<String, dynamic> user, bool active) async {
    try { await _api.patch('/auth/admin/users/', {'user_id': user['id'], 'is_active': active}); if (mounted) setState(() => user['is_active'] = active); }
    catch (e) { if (mounted) LoopinSnackBar.show(context, e.toString()); }
  }

  Future<void> _editLimit() async {
    final controller = TextEditingController(text: maxUsers == 0 ? '' : maxUsers.toString());
    final value = await showDialog<int>(context: context, builder: (context) => AlertDialog(
      title: const Text('User limit'),
      content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: '0 = unlimited', labelText: 'Maximum users')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim()) ?? 0), child: const Text('Save'))],
    ));
    controller.dispose(); if (value == null) return;
    try { final response = await _api.patch('/auth/admin/user-limit/', {'max_users': value}); if (mounted) setState(() { maxUsers = response['max_users'] ?? value; totalUsers = response['total_users'] ?? totalUsers; }); }
    catch (e) { if (mounted) LoopinSnackBar.show(context, e.toString()); }
  }

  Future<void> _loadListening({bool reset = false}) async {
    if (loadingPage) return; final targetPage = reset ? 1 : page + 1; setState(() => loadingPage = true);
    try {
      final response = await _api.get('/listening/admin/listening/?type=$filter&page=$targetPage&page_size=25');
      if (!mounted) return; final incoming = List<Map<String, dynamic>>.from((response['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
      setState(() { listening = reset ? incoming : [...listening, ...incoming]; page = targetPage; totalListening = response['total'] ?? totalListening; hasNext = response['has_next'] == true; loadingPage = false; });
    } catch (e) { if (mounted) { setState(() => loadingPage = false); LoopinSnackBar.show(context, e.toString()); } }
  }
  Future<void> _setFilter(String value) async { if (filter == value) return; setState(() => filter = value); await _loadListening(reset: true); }
  Future<void> _toggleService(Map<String, dynamic> row, bool value) async { try { await _api.patch('/catalog/admin/services/', {'key': row['key'], 'enabled': value}); if (mounted) setState(() => row['enabled'] = value); } catch (e) { if (mounted) LoopinSnackBar.show(context, e.toString()); } }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Loopin Admin'), bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Users'), Tab(text: 'Listening'), Tab(text: 'Services')])),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: TabBarView(controller: _tabs, children: [_usersTab(), _listeningTab(), _servicesTab()]),
            ),
          ),
  );

  Widget _usersTab() => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: ListTile(leading: const Icon(Icons.people_alt_rounded), title: Text('$totalUsers / ${maxUsers == 0 ? '∞' : maxUsers} users'), subtitle: const Text('Registration limit for non-admin accounts.'), trailing: IconButton(icon: const Icon(Icons.edit_rounded), onPressed: _editLimit))),
    const SizedBox(height: 12),
    ...users.map((u) => Card(child: SwitchListTile(value: u['is_active'] == true, onChanged: u['is_staff'] == true ? null : (v) => _setUserActive(u, v), title: Text((u['email']?.toString().isNotEmpty == true) ? u['email'].toString() : u['username'].toString()), subtitle: Text(u['is_staff'] == true ? 'Administrator' : (u['is_active'] == true ? 'Active' : 'Disabled'))))),
  ]));

  Widget _listeningTab() => RefreshIndicator(onRefresh: () => _loadListening(reset: true), child: ListView(padding: const EdgeInsets.all(16), children: [
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [ChoiceChip(label: const Text('History'), selected: filter == 'history', onSelected: (_) => _setFilter('history')), const SizedBox(width: 8), ChoiceChip(label: const Text('Liked'), selected: filter == 'like', onSelected: (_) => _setFilter('like')), const SizedBox(width: 8), ChoiceChip(label: const Text('Disliked'), selected: filter == 'dislike', onSelected: (_) => _setFilter('dislike')), const SizedBox(width: 8), ChoiceChip(label: const Text('All'), selected: filter == 'all', onSelected: (_) => _setFilter('all'))])),
    const SizedBox(height: 12), Text('$totalListening records', style: const TextStyle(color: Colors.white54)), const SizedBox(height: 8),
    ...listening.map((item) => Card(child: ListTile(leading: _cover(item['image_url']?.toString() ?? ''), title: Text(item['title']?.toString() ?? 'Unknown song', maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${item['artist'] ?? 'Unknown artist'} • ${item['email'] ?? 'Unknown user'}\n${item['event_type'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis)))),
    if (hasNext) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: OutlinedButton.icon(onPressed: loadingPage ? null : () => _loadListening(), icon: loadingPage ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more_rounded), label: Text(loadingPage ? 'Loading…' : 'Load more'))),
    const SizedBox(height: 40),
  ]));

  Widget _cover(String url) => ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 48, child: ColoredBox(color: Color(0xff1c1c1c), child: Icon(Icons.music_note_rounded)))));
  Widget _servicesTab() => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [const Text('Service controls', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)), const SizedBox(height: 8), ...services.map((row) => Card(child: SwitchListTile(value: row['enabled'] == true, onChanged: (value) => _toggleService(row, value), title: Text(row['label'] ?? row['key']), subtitle: Text((row['message'] ?? '').toString().isNotEmpty ? row['message'].toString() : row['key'].toString()))))]));
}