import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'api.dart';
import 'screens.dart';
import 'receipt.dart';
import 'design.dart';

void main() => runApp(const ProviderScope(child: BasketWiseApp()));

final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const SessionGate()),
    GoRoute(
      path: '/review/:id',
      builder: (_, state) => ReviewScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/orders/:id',
      builder: (_, state) => DetailScreen(id: state.pathParameters['id']!),
    ),
  ],
);

class BasketWiseApp extends ConsumerWidget {
  const BasketWiseApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return MaterialApp.router(
      title: 'BasketWise',
      debugShowCheckedModeBanner: false,
      theme: BasketStyle.theme(Brightness.light),
      darkTheme: BasketStyle.theme(Brightness.dark),
      themeMode: theme == 'dark'
          ? ThemeMode.dark
          : theme == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      routerConfig: router,
    );
  }
}

class SessionGate extends ConsumerStatefulWidget {
  const SessionGate({super.key});
  @override
  ConsumerState<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends ConsumerState<SessionGate> {
  bool ready = false;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final signedIn = await ref.read(apiProvider).restore();
    if (!mounted) return;
    if (signedIn) {
      try {
        final profile = await ref.read(apiProvider).get('profile/');
        if (mounted) ref.read(themeProvider.notifier).state = profile['theme'];
      } catch (_) {}
    }
    if (!mounted) return;
    ref.read(sessionProvider.notifier).state = signedIn;
    setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) => !ready
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : ref.watch(sessionProvider)
      ? const AppShell()
      : const AuthScreen();
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    return Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: [
            const HomeScreen(),
            const OrdersScreen(),
            const ScanScreen(),
            const AnalyticsScreen(),
            const ProfileScreen(),
          ][index],
        ),
      ),
    ),
    bottomNavigationBar: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) =>
            ref.read(shellTabProvider.notifier).state = value,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_rounded),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    ),
  );
  }
}
