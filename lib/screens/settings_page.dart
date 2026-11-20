import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/realtime_player_service.dart';
import '../services/sync_player_service.dart';
import 'audio_settings_page.dart';
import 'admin_page.dart';
import 'login_page.dart';
import 'profile_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool staff = false;
  bool _isLoggedIn = false;
  bool _standaloneMode = false;
  bool _modeLoading = true;
  bool _modeUpdating = false;

  void _checkAuth() {
    AuthService().restore().then((u) {
      if (mounted) {
        setState(() {
          staff = u?.isStaff == true;
          _isLoggedIn = u != null;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _checkAuth();
    Future.wait([
      RealtimePlayerService().initializeMode(),
      SyncPlayerService().initializeMode(),
    ]).then((_) {
      if (!mounted) return;
      setState(() {
        _standaloneMode = RealtimePlayerService().standaloneMode;
        _modeLoading = false;
      });
    });
  }

  Future<void> _setStandaloneMode(bool enabled) async {
    if (_modeUpdating) return;
    setState(() => _modeUpdating = true);
    try {
      // Stop both the cloud player socket and any active LAN Sync socket/group.
      await RealtimePlayerService().setStandaloneMode(enabled);
      await SyncPlayerService().setStandaloneMode(enabled);
      if (mounted) setState(() => _standaloneMode = enabled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change connection mode: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _modeUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      const Text(
        'Account',
        style: TextStyle(
          fontSize: 14,
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      _card(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: const Text('Profile'),
            subtitle: Text(_isLoggedIn ? 'Account details from Loopin' : 'View account profile'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ).then((_) => _checkAuth()),
          ),
          if (!_isLoggedIn) ...[
            const Divider(height: 1, color: AppColors.divider),
            ListTile(
              leading: const Icon(Icons.login_rounded, color: AppColors.accent),
              title: const Text('Sign in (optional)'),
              subtitle: const Text('Log in to sync favorites and listening rooms'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              ).then((_) => _checkAuth()),
            ),
          ],
        ],
      ),
      if (!_isLoggedIn) ...[
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ).then((_) => _checkAuth()),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in (optional)'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 24),
      const Text(
        'Playback',
        style: TextStyle(
          fontSize: 14,
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      _card(
        children: [
          ListTile(
            leading: const Icon(Icons.graphic_eq_rounded),
            title: const Text('Audio quality & effects'),
            subtitle: const Text('Quality, balance, mono and equalizer'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AudioSettingsPage()),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          const ListTile(
            leading: Icon(Icons.notifications_none_rounded),
            title: Text('Notifications'),
            subtitle: Text('Playback controls and updates'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          const Divider(height: 1, color: AppColors.divider),
          SwitchListTile(
            secondary: Icon(
              _standaloneMode
                  ? Icons.cloud_off_rounded
                  : Icons.cloud_sync_rounded,
            ),
            title: const Text('Standalone mode'),
            subtitle: Text(
              _modeLoading
                  ? 'Checking connection mode…'
                  : _standaloneMode
                  ? 'WebSocket connections are disabled. Playback stays on this device.'
                  : 'Keep Loopin connected for remote playback and Sync features.',
            ),
            value: _standaloneMode,
            onChanged: _modeLoading || _modeUpdating
                ? null
                : _setStandaloneMode,
          ),
        ],
      ),
    ];
    if (staff) {
      children.addAll([
        const SizedBox(height: 24),
        const Text(
          'Administration',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _card(
          children: [
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Loopin Admin'),
              subtitle: const Text('Switch services and inspect liked songs'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPage()),
              ),
            ),
          ],
        ),
      ]);
    }
    children.addAll([
      const SizedBox(height: 24),
      const Text(
        'About',
        style: TextStyle(
          fontSize: 14,
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      _card(
        children: const [
          ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('About Loopin'),
            subtitle: Text('A simple place for music you want to repeat.'),
          ),
          ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Privacy'),
            subtitle: Text(
              'Your account data and listening settings are stored securely.',
            ),
          ),
        ],
      ),
    ]);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}
