import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../features/home/presentation/home_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/player/presentation/widgets/mini_player.dart';
import '../features/search/presentation/search_page.dart';
import '../features/settings/presentation/settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  int _previousIndex = 0;

  late final AnimationController _animationController;

  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();

  final List<Widget> _pages = const [
    HomePage(),
    LibraryPage(),
    SearchPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) {
      return;
    }

    final navigator = _contentNavigatorKey.currentState;

    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }

    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
    });

    _animationController.forward(from: 0);
  }

  Future<bool> _handleBack() async {
    final navigator = _contentNavigatorKey.currentState;

    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return false;
    }

    if (_selectedIndex != 0) {
      setState(() {
        _previousIndex = _selectedIndex;
        _selectedIndex = 0;
      });

      _animationController.forward(from: 0);

      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final showMiniPlayer = _selectedIndex != 3;
    final movingForward = _selectedIndex > _previousIndex;

    final titles = [l10n.appName, l10n.library, l10n.search, l10n.settings];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }

        final shouldExit = await _handleBack();

        if (shouldExit && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 76,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 24,
          title: Text(
            titles[_selectedIndex],
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Navigator(
                key: _contentNavigatorKey,
                onGenerateRoute: (settings) {
                  return MaterialPageRoute(
                    settings: settings,
                    builder: (context) {
                      return _AnimatedPage(
                        animation: _animationController,
                        movingForward: movingForward,
                        child: IndexedStack(
                          index: _selectedIndex,
                          children: _pages,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (showMiniPlayer) const MiniPlayer(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onDestinationSelected,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home),
              label: l10n.home,
            ),
            NavigationDestination(
              icon: const Icon(Icons.library_music_outlined),
              selectedIcon: const Icon(Icons.library_music),
              label: l10n.library,
            ),
            NavigationDestination(
              icon: const Icon(Icons.search),
              label: l10n.search,
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: l10n.settings,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedPage extends StatelessWidget {
  final Animation<double> animation;
  final bool movingForward;
  final Widget child;

  const _AnimatedPage({
    required this.animation,
    required this.movingForward,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );

    final offsetAnimation = Tween<Offset>(
      begin: Offset(movingForward ? 0.03 : -0.03, 0),
      end: Offset.zero,
    ).animate(curvedAnimation);

    return FadeTransition(
      opacity: curvedAnimation,
      child: SlideTransition(position: offsetAnimation, child: child),
    );
  }
}
