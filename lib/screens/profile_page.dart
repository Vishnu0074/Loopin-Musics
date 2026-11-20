import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/auth_bloc.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/achievement_section.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _api = AuthService();
  AuthUser? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _api.get('/auth/me/');
      if (!mounted) return;
      setState(() {
        _user = AuthUser.fromJson(data);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your profile', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 12, wide ? 32 : 20, 40),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _profileHero(user),
                        const SizedBox(height: 24),
                        const AchievementSection(),
                        const SizedBox(height: 28),
                        if (_loading && user == null)
                          const Padding(
                            padding: EdgeInsets.all(36),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_error != null && user == null)
                          _errorCard()
                        else if (user != null) ...[
                          _sectionHeading('ACCOUNT DETAILS', 'Your personal information'),
                          const SizedBox(height: 12),
                          _detailsCard(user, wide),
                          const SizedBox(height: 24),
                          _sectionHeading('ACCOUNT', 'Manage your Loopin session'),
                          const SizedBox(height: 12),
                          _accountCard(user),
                          const SizedBox(height: 28),
                          _logoutButton(),
                          const SizedBox(height: 16),
                          const Center(
                            child: Text(
                              'MADE FOR THE LOVE OF MUSIC',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 10,
                                letterSpacing: 2.0,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _profileHero(AuthUser? user) {
    final name = user == null ? 'Loopin listener' : _displayName(user);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF28202A), Color(0xFF191619), Color(0xFF121212)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -22,
            top: -34,
            child: Icon(Icons.graphic_eq_rounded, size: 150, color: AppColors.accent.withValues(alpha: 0.07)),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.8), width: 1.5),
                  boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.16), blurRadius: 24)],
                ),
                child: CircleAvatar(
                  radius: 42,
                  backgroundColor: const Color(0xFF30232D),
                  child: Text(
                    _initials(user),
                    style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text(user?.email ?? (_loading ? 'Loading your account…' : 'Your music profile'),
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.graphic_eq_rounded, color: AppColors.accent, size: 15),
                    const SizedBox(width: 7),
                    Text(user?.isStaff == true ? 'LOOPIN ADMIN' : 'LOOPIN LISTENER',
                      style: const TextStyle(color: AppColors.accent, fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(color: AppColors.accent, fontSize: 10, letterSpacing: 1.7, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(subtitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
    ],
  );

  Widget _detailsCard(AuthUser user, bool wide) {
    final fields = [
      _detail(Icons.alternate_email_rounded, 'Username', user.username),
      _detail(Icons.mail_outline_rounded, 'Email address', user.email),
      _detail(Icons.phone_iphone_rounded, 'Phone number', user.phoneNumber),
      _detail(Icons.verified_user_outlined, 'Account type', user.isStaff ? 'Staff / Admin' : 'Listener'),
    ];
    return Container(
      decoration: _cardDecoration(),
      child: wide
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 4.3,
                children: fields,
              ),
            )
          : Column(children: [
              for (var i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i != fields.length - 1) Divider(height: 1, indent: 58, color: Colors.white.withValues(alpha: 0.06)),
              ],
            ]),
    );
  }

  Widget _detail(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.045), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 18, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value.isEmpty ? 'Not provided' : value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    ),
  );

  Widget _accountCard(AuthUser user) => Container(
    decoration: _cardDecoration(),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(13)),
        child: const Icon(Icons.shield_outlined, color: AppColors.accent, size: 20),
      ),
      title: const Text('Account status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      subtitle: Text(user.isStaff ? 'Privileged account' : 'Your Loopin account is ready', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      trailing: const Icon(Icons.check_circle_rounded, color: Color(0xFF6FCF97), size: 20),
    ),
  );

  Widget _errorCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_rounded, color: AppColors.accent, size: 30),
        const SizedBox(height: 10),
        const Text('Couldn’t load your profile', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(_error ?? 'Something went wrong.', textAlign: TextAlign.center,
          maxLines: 3, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 14),
        OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())),
          icon: const Icon(Icons.login_rounded),
          label: const Text('Sign in (optional)'),
        ),
      ],
    ),
  );

  Widget _logoutButton() => OutlinedButton.icon(
    onPressed: _logout,
    icon: const Icon(Icons.logout_rounded, size: 18),
    label: const Text('Log out'),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFFF6B81),
      side: BorderSide(color: const Color(0xFFFF6B81).withValues(alpha: 0.28)),
      backgroundColor: const Color(0xFFFF6B81).withValues(alpha: 0.055),
      minimumSize: const Size.fromHeight(54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
  );

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to access your account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<AuthBloc>().add(const LogoutRequested());
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String _displayName(AuthUser user) {
    final name = '${user.firstName} ${user.lastName}'.trim();
    return name.isEmpty ? user.username : name;
  }

  String _initials(AuthUser? user) {
    if (user == null) return 'L';
    final name = _displayName(user).trim();
    final parts = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.length >= 2) return (parts.first[0] + parts.last[0]).toUpperCase();
    return name.isEmpty ? 'L' : name.substring(0, 1).toUpperCase();
  }
}
