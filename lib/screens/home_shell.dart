import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/library_bloc.dart';
import '../services/playlist_service.dart';
import '../theme/app_theme.dart';
import 'discover_page.dart';
import 'home.dart';
import 'library_page.dart';
import 'mini_player.dart';
import 'sync_page.dart';
import 'listen_together_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final LibraryBloc _libraryBloc;
  bool _libraryLoaded = false;

  @override
  void initState() {
    super.initState();
    _libraryBloc = LibraryBloc(PlaylistService());
  }

  @override
  void dispose() {
    _libraryBloc.close();
    super.dispose();
  }

  static const _pages = <Widget>[
    HomePage(),
    SyncPage(),
    ListenTogetherPage(),
    DiscoverPage(),
    LibraryPage(),
  ];

  void _selectTab(int value) {
    if (value == 4 && !_libraryLoaded) {
      _libraryLoaded = true;
      _libraryBloc.add(const LibraryRequested());
    }
    setState(() => _index = value);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _libraryBloc,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          final isWide = constraints.maxWidth >= 1150;
          final content = IndexedStack(index: _index, children: _pages);
          if (desktop) {
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    extended: isWide,
                    minWidth: 88,
                    minExtendedWidth: 200,
                    selectedIndex: _index,
                    onDestinationSelected: _selectTab,
                    labelType: isWide
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 16,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.graphic_eq_rounded,
                            color: Colors.pinkAccent,
                            size: 30,
                          ),
                          if (isWide) ...[
                            const SizedBox(width: 12),
                            const Text(
                              'Loopin',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: Text('Home'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.sensors_rounded),
                        selectedIcon: Icon(Icons.sensors_rounded),
                        label: Text('Sync'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.headphones_outlined),
                        selectedIcon: Icon(Icons.headphones_rounded),
                        label: Text('Together'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.explore_outlined),
                        selectedIcon: Icon(Icons.explore_rounded),
                        label: Text('Discover'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.library_music_outlined),
                        selectedIcon: Icon(Icons.library_music_rounded),
                        label: Text('Library'),
                      ),
                    ],
                  ),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Colors.white10,
                  ),
                  Expanded(child: content),
                ],
              ),
              bottomNavigationBar: const MiniPlayer(),
            );
          }
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(child: content),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const MiniPlayer(),
                      _FloatingPillNavigationBar(
                        selectedIndex: _index,
                        onDestinationSelected: _selectTab,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FloatingPillNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const _FloatingPillNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  static const _items = [
    _NavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _NavItem(
      label: 'Sync',
      icon: Icons.sensors_outlined,
      selectedIcon: Icons.sensors_rounded,
    ),
    _NavItem(
      label: 'Together',
      icon: Icons.headphones_outlined,
      selectedIcon: Icons.headphones_rounded,
    ),
    _NavItem(
      label: 'Discover',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
    ),
    _NavItem(
      label: 'Library',
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomMargin = bottomInset > 0 ? bottomInset + 4 : 14.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 6, 20, bottomMargin),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 24,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF222228).withValues(alpha: 0.45),
                        const Color(0xFF141418).withValues(alpha: 0.30),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(_items.length, (index) {
                      final item = _items[index];
                      final isSelected = selectedIndex == index;
                      return _PillTabItem(
                        item: item,
                        isSelected: isSelected,
                        onTap: () => onDestinationSelected(index),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _PillTabItem extends StatelessWidget {
  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _PillTabItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: item.label,
      waitDuration: const Duration(milliseconds: 600),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: AppColors.accent.withValues(alpha: 0.18),
          highlightColor: AppColors.accent.withValues(alpha: 0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isSelected ? 16 : 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.accent.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.38)
                    : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? item.selectedIcon : item.icon,
                  size: 22,
                  color: isSelected ? AppColors.accent : AppColors.muted,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  child: isSelected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            item.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
