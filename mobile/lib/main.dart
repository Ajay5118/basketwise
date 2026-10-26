import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'api.dart';
import 'screens.dart';
import 'receipt.dart';

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
    ThemeData makeTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff227c66),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff5f7f6)
          : const Color(0xff101917),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
    return MaterialApp.router(
      title: 'BasketWise',
      debugShowCheckedModeBanner: false,
      theme: makeTheme(Brightness.light),
      darkTheme: makeTheme(Brightness.dark),
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
  int index = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
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
    bottomNavigationBar: NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) => setState(() => index = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          selectedIcon: Icon(Icons.space_dashboard),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'Orders',
        ),
        NavigationDestination(
          icon: Icon(Icons.document_scanner_outlined),
          label: 'Scan',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_rounded),
          label: 'Analytics',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          label: 'Profile',
        ),
      ],
    ),
  );
}
