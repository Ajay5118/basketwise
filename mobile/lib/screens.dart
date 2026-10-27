import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'api.dart';
import 'widgets.dart';
import 'order_filters.dart';
import 'design.dart';
import 'fees.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool register = false, consent = false, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .authenticate(email.text, password.text, register);
      ref.read(sessionProvider.notifier).state = true;
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool hidePassword = true;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 490),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const BrandMark(compact: true),
                  Icon(
                    Icons.eco_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const ReceiptHero(),
              const SizedBox(height: 30),
              Eyebrow(
                register ? 'A FRESH START' : 'YOUR MONEY, A LITTLE CLEARER',
              ),
              const SizedBox(height: 8),
              Text(
                register
                    ? 'Your next chapter starts here.'
                    : 'Good to see you.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                register
                    ? 'One place for your grocery receipts and spending.'
                    : 'Sign in and pick up where your last basket left off.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              AutofillGroup(
                child: Column(
                  children: [
                    TextField(
                      controller: email,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(
                          Icons.alternate_email_rounded,
                          size: 20,
                        ),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(
                          Icons.lock_outline_rounded,
                          size: 20,
                        ),
                        suffixIcon: IconButton(
                          tooltip: hidePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () =>
                              setState(() => hidePassword = !hidePassword),
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                      obscureText: hidePassword,
                      autofillHints: [
                        register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onSubmitted: (_) {
                        if (!busy && (!register || consent)) submit();
                      },
                    ),
                  ],
                ),
              ),
              if (!register)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ResetScreen()),
                    ),
                    child: const Text('Forgot password?'),
                  ),
                ),
              if (register)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: consent,
                    onChanged: (value) => setState(() => consent = value!),
                    title: const Text(
                      'I consent to processing my uploaded receipts and accept the privacy policy.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: busy || (register && !consent) ? null : submit,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Text(
                      busy
                          ? 'Please wait…'
                          : register
                          ? 'Create account'
                          : 'Sign in',
                    ),
                    const SizedBox(width: 12),
                    if (!busy)
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        register = !register;
                        error = null;
                      }),
                child: Text(
                  register
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Your receipts. Your control.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              TextButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('Your privacy'),
                    content: SingleChildScrollView(
                      child: Text(
                        'BasketWise processes only the documents you upload. Receipt files are private and removed after the configured retention period, 30 days by default. Saved orders remain until you delete them or your account. No SMS inbox access or merchant credentials are required. You can export or delete your data from Profile.',
                      ),
                    ),
                  ),
                ),
                child: const Text(
                  'Privacy policy',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ResetScreen extends ConsumerStatefulWidget {
  const ResetScreen({super.key});
  @override
  ConsumerState<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends ConsumerState<ResetScreen> {
  final email = TextEditingController(),
      uid = TextEditingController(),
      token = TextEditingController(),
      password = TextEditingController();
  String message =
      'Request instructions, then enter the values from your email.';
  bool busy = false;
  @override
  void dispose() {
    for (final c in [email, uid, token, password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(bool confirm) async {
    setState(() => busy = true);
    try {
      final result = await ref
          .read(apiProvider)
          .post(
            confirm ? 'auth/password-reset/confirm/' : 'auth/password-reset/',
            confirm
                ? {
                    'uid': uid.text,
                    'token': token.text,
                    'password': password.text,
                  }
                : {'email': email.text},
          );
      if (mounted) setState(() => message = result['detail']);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: PageBody(
      title: 'Recover access',
      subtitle: message,
      children: [
        TextField(
          controller: email,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        FilledButton(
          onPressed: busy ? null : () => run(false),
          child: const Text('Send reset email'),
        ),
        TextField(
          controller: uid,
          decoration: const InputDecoration(labelText: 'User value from email'),
        ),
        TextField(
          controller: token,
          decoration: const InputDecoration(labelText: 'Reset token'),
        ),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password'),
        ),
        FilledButton(
          onPressed: busy ? null : () => run(true),
          child: const Text('Set new password'),
        ),
      ],
    ),
  );
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<dynamic> data;
  DateTimeRange? range;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final query = <String, dynamic>{
      if (range != null)
        'start': range!.start.toIso8601String().substring(0, 10),
      if (range != null) 'end': range!.end.toIso8601String().substring(0, 10),
    };
    data = Future.wait([
      ref.read(apiProvider).get('analytics/overview/', query: query),
      ref.read(apiProvider).get('orders/', query: query),
      ref.read(apiProvider).get('analytics/fees/'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(revisionProvider, (_, _) => setState(load));
    ref.listen<String?>(homeBannerProvider, (previous, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next), behavior: SnackBarBehavior.floating),
        );
        ref.read(homeBannerProvider.notifier).state = null;
      });
    });
    return RemoteData(
      future: data,
      retry: () => setState(load),
      builder: (result) {
        final summary = result[0] as Json,
            recent = result[1]['results'] as List,
            fees = Json.from(result[2] as Map);
        return RefreshIndicator(
          onRefresh: () async {
            setState(load);
            await data;
          },
          child: PageBody(
            title: 'Every basket,\na clearer picture.',
            subtitle: 'Your grocery spending, thoughtfully organised.',
            action: IconButton(
              tooltip: 'Filter dates',
              icon: const Icon(Icons.date_range_outlined),
              onPressed: () async {
                final chosen = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: range,
                );
                if (chosen != null && mounted) {
                  setState(() {
                    range = chosen;
                    load();
                  });
                }
              },
            ),
            children: [
              Container(
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    colors: [Color(0xff123f36), Color(0xff1b6753)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Eyebrow(
                          'YOUR MONTH IN A BASKET',
                          color: Color(0xffc0dfce),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Color(0xffd8ecdf),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'THIS MONTH · NET SPENDING',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        rupees(summary['this_month']['net_spending']),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 43,
                          letterSpacing: -1.6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Last month ${rupees(summary['last_month']['net_spending'])}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      summary['change_percent'] == null
                          ? 'No prior-month comparison yet'
                          : '${summary['change_percent']}% compared with last month',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 14) / 2;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _metric(
                        'Orders',
                        summary['order_count'].toString(),
                        Icons.receipt_long,
                        width,
                      ),
                      _metric(
                        'Average order',
                        rupees(summary['average_order_value']),
                        Icons.shopping_bag_outlined,
                        width,
                      ),
                    ],
                  );
                },
              ),
              FeeHighlight(data: fees, onTap: () => context.push('/fees')),
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => ref.read(shellTabProvider.notifier).state = 2,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light
                        ? const Color(0xffedece0)
                        : const Color(0xff293a30),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Import a receipt',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'A new basket, a clearer picture.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, size: 19),
                    ],
                  ),
                ),
              ),
              if (range != null)
                SoftNotice(
                  icon: Icons.date_range_outlined,
                  title: 'Your selected date range',
                  text:
                      'Net spending ${rupees(summary['net_spending'])} across ${summary['order_count']} orders. The main card always shows this month.',
                ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Where you shop',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if ((summary['platforms'] as List).isEmpty)
                      EmptyState(
                        icon: Icons.storefront_outlined,
                        title: 'No shops yet',
                        message:
                            'After you save a purchase, you’ll see where you spend most.',
                        action: FilledButton.tonal(
                          onPressed: () =>
                              ref.read(shellTabProvider.notifier).state = 2,
                          child: const Text('Add a receipt'),
                        ),
                      )
                    else
                      for (final platform in summary['platforms'])
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            platformLabel(platform['label'].toString()),
                          ),
                          trailing: Text(rupees(platform['amount'])),
                        ),
                  ],
                ),
              ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your latest baskets',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (recent.isEmpty)
                      EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No saved baskets yet',
                        message:
                            'Scan or upload a receipt, review the details, then save.',
                        action: FilledButton.tonal(
                          onPressed: () =>
                              ref.read(shellTabProvider.notifier).state = 2,
                          child: const Text('Scan a receipt'),
                        ),
                      ),
                    for (final order in recent.take(5))
                      OrderTile(
                        order: Json.from(order),
                        onTap: () => context.push('/orders/${order['id']}'),
                      ),
                  ],
                ),
              ),
              const Text(
                'Only confirmed delivered/refunded purchases count toward spending. Pending payments stay separate.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metric(String title, String value, IconData icon, double width) =>
      SizedBox(
        width: width,
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: BasketStyle.mint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: BasketStyle.green, size: 18),
              ),
              const SizedBox(height: 16),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final search = TextEditingController();
  String platform = '', status = '';
  int page = 1;
  late Future<dynamic> data;
  final filters = <String, dynamic>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void load() {
    data = ref
        .read(apiProvider)
        .get(
          'orders/',
          query: {
            'page': page,
            'search': search.text,
            if (platform.isNotEmpty) 'platform': platform,
            if (status.isNotEmpty) 'status': status,
            ...filters,
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(revisionProvider, (_, _) => setState(load));
    return RemoteData(
      future: data,
      retry: () => setState(load),
      builder: (result) => PageBody(
        title: 'Your baskets',
        subtitle: '${result['count']} saved purchases',
        children: [
          TextField(
            controller: search,
            decoration: InputDecoration(
              labelText: 'Search products or amounts',
              prefixIcon: const Icon(Icons.search_rounded, size: 22),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => setState(() {
                  page = 1;
                  load();
                }),
              ),
            ),
            onSubmitted: (_) => setState(() {
              page = 1;
              load();
            }),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final chosen = await showDialog<Json>(
                  context: context,
                  builder: (context) => OrderFilters(initial: filters),
                );
                if (chosen != null && mounted) {
                  setState(() {
                    filters.clear();
                    filters.addAll(chosen);
                    page = 1;
                    load();
                  });
                }
              },
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Filters'),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: platform,
                  decoration: const InputDecoration(labelText: 'Shop'),
                  items: [
                    for (final p in [
                      '',
                      'instamart',
                      'blinkit',
                      'zepto',
                      'bigbasket',
                      'other',
                    ])
                      DropdownMenuItem(
                        value: p,
                        child: Text(p.isEmpty ? 'All shops' : platformLabel(p)),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    platform = v!;
                    page = 1;
                    load();
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final s in [
                      '',
                      'delivered',
                      'cancelled',
                      'pending',
                      'refunded',
                      'unknown',
                    ])
                      DropdownMenuItem(
                        value: s,
                        child: Text(
                          s.isEmpty ? 'Any status' : orderStatusLabel(s),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    status = v!;
                    page = 1;
                    load();
                  }),
                ),
              ),
            ],
          ),
          if ((result['results'] as List).isEmpty)
            EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Nothing matched',
              message:
                  'Try a different search or add a receipt from the Scan tab.',
              action: FilledButton.tonal(
                onPressed: () => ref.read(shellTabProvider.notifier).state = 2,
                child: const Text('Go to Scan'),
              ),
            )
          else
            for (final order in result['results'])
              Panel(
                child: OrderTile(
                  order: Json.from(order),
                  onTap: () => context.push('/orders/${order['id']}'),
                ),
              ),
          if ((result['results'] as List).isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: page > 1
                      ? () => setState(() {
                          page--;
                          load();
                        })
                      : null,
                  child: const Text('Previous'),
                ),
                Text('Page $page'),
                TextButton(
                  onPressed: result['next'] != null
                      ? () => setState(() {
                          page++;
                          load();
                        })
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  late Future<dynamic> data;
  String interval = 'monthly';
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final api = ref.read(apiProvider);
    data = Future.wait([
      api.get('analytics/$interval/'),
      api.get('analytics/categories/'),
      api.get('analytics/platforms/'),
      api.get('analytics/products/'),
    ]);
  }

  @override
  Widget build(BuildContext context) => RemoteData(
    future: data,
    retry: () => setState(load),
    builder: (result) {
      final rows = result[0] as List;
      return PageBody(
        title: 'Meet your\nspending habits.',
        subtitle: 'Understand the habits behind your spending.',
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'monthly', label: Text('Monthly')),
              ButtonSegment(value: 'weekly', label: Text('Weekly')),
            ],
            selected: {interval},
            onSelectionChanged: (v) => setState(() {
              interval = v.first;
              load();
            }),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Net spending',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                if (rows.isEmpty)
                  EmptyState(
                    icon: Icons.bar_chart_rounded,
                    title: 'No spending chart yet',
                    message:
                        'Save your first purchase to see how spending changes over time.',
                    action: FilledButton.tonal(
                      onPressed: () =>
                          ref.read(shellTabProvider.notifier).state = 2,
                      child: const Text('Add a receipt'),
                    ),
                  )
                else
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        barGroups: [
                          for (var i = 0; i < rows.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: double.parse(rows[i]['amount']),
                                  width: 24,
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                for (final row in rows)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row['label']),
                    trailing: Text(rupees(row['amount'])),
                  ),
              ],
            ),
          ),
          for (final group in [
            (1, 'Product categories · before fees and refunds'),
            (2, 'Platform comparison · net'),
          ])
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.$2,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if ((result[group.$1] as List).isEmpty)
                    const Text('No data yet.'),
                  for (final row in result[group.$1])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row['label']),
                      trailing: Text(rupees(row['amount'])),
                    ),
                ],
              ),
            ),
          const Text(
            'Categories remain Uncategorized until you assign them during review. Unknown values are never estimated.',
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your regulars',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if ((result[3] as List).isEmpty)
                  const Text('Frequently purchased products will appear here.'),
                for (final product in result[3])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(product['name']),
                    subtitle: Text(
                      '${product['orders']} orders · known quantity ${product['quantity']}',
                    ),
                    trailing: Text(rupees(product['spending'])),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late Future<dynamic> data;
  final budget = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    data = ref.read(apiProvider).get('profile/');
  }

  @override
  void dispose() {
    budget.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RemoteData(
    future: data,
    retry: () => setState(load),
    builder: (profile) => PageBody(
      title: 'Make it yours.',
      subtitle: profile['email'],
      children: [
        SoftNotice(
          icon: Icons.person_outline_rounded,
          title: 'Your personal space',
          text:
              'Set your budget, choose your look and keep control of your data.',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your preferences',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: ref.watch(themeProvider),
                decoration: const InputDecoration(labelText: 'Appearance'),
                items: [
                  for (final theme in ['system', 'light', 'dark'])
                    DropdownMenuItem(
                      value: theme,
                      child: Text(switch (theme) {
                        'light' => 'Light',
                        'dark' => 'Dark',
                        _ => 'Match device',
                      }),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => run(() async {
                        await ref.read(apiProvider).patch('profile/', {
                          'theme': value,
                        });
                        ref.read(themeProvider.notifier).state = value!;
                      }),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: budget,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Monthly budget (₹)',
                  hintText: profile['monthly_budget'] ?? 'Not set',
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await ref.read(apiProvider).patch('profile/', {
                          'monthly_budget': budget.text.isEmpty
                              ? null
                              : budget.text,
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Budget saved')),
                          );
                        }
                      }),
                child: const Text('Save budget'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: profile['notifications'],
                title: const Text('Notification preference'),
                subtitle: const Text(
                  'Stored for future opt-in alerts; push delivery is not enabled.',
                ),
                onChanged: busy
                    ? null
                    : (v) => run(() async {
                        await ref.read(apiProvider).patch('profile/', {
                          'notifications': v,
                        });
                        setState(load);
                      }),
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline),
                title: Text('Your data belongs to you'),
                subtitle: Text(
                  'Private receipt processing. No SMS access. No connected shopping credentials.',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export all data'),
                onTap: busy
                    ? null
                    : () => run(() async {
                        final export = await ref
                            .read(apiProvider)
                            .get('export/');
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [
                              XFile.fromData(
                                utf8.encode(
                                  const JsonEncoder.withIndent(
                                    '  ',
                                  ).convert(export),
                                ),
                                mimeType: 'application/json',
                              ),
                            ],
                            fileNameOverrides: ['basketwise-export.json'],
                          ),
                        );
                      }),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Bank payment alerts'),
                subtitle: const Text('Import a debit alert manually'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaymentsScreen()),
                ),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.mail_outline),
                title: Text('Connected accounts'),
                subtitle: Text(
                  'Email sync is not available. OAuth and consent review are required.',
                ),
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  await ref.read(apiProvider).logout();
                  ref.read(sessionProvider.notifier).state = false;
                }),
          child: const Text('Sign out'),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  final password = await _input(
                    context,
                    'Delete your account',
                    'Enter your password. All orders, payments and uploaded files will be permanently deleted.',
                    secret: true,
                  );
                  if (password == null || !context.mounted) return;
                  if (!await approve(
                    context,
                    'Permanently delete account?',
                    'This cannot be undone.',
                  )) {
                    return;
                  }
                  await ref
                      .read(apiProvider)
                      .delete('account/', data: {'password': password});
                  await ref.read(apiProvider).storage.deleteAll();
                  ref.read(apiProvider).access = null;
                  ref.read(sessionProvider.notifier).state = false;
                }),
          child: Text(
            'Delete account and all data',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
  );
}

Future<String?> _input(
  BuildContext context,
  String title,
  String message, {
  bool secret = false,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            obscureText: secret,
            maxLines: secret ? 1 : 4,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  // Dialog route may still be animating; controller is released after the frame.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});
  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  late Future<dynamic> data;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    data = ref.read(apiProvider).get('payments/');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment alerts')),
    body: RemoteData(
      future: data,
      retry: () => setState(load),
      builder: (result) => PageBody(
        title: 'Payments detected',
        subtitle: 'Payments remain separate from confirmed order spending.',
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Paste debit alert'),
            onPressed: () async {
              final text = await _input(
                context,
                'Import bank alert',
                'Paste the debit alert. Account numbers and UPI identifiers are not retained.',
              );
              if (text == null) return;
              try {
                await ref.read(apiProvider).post('payments/import/', {
                  'text': text,
                });
                if (mounted) setState(load);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
          ),
          for (final payment in result['results'])
            Panel(
              child: ListTile(
                title: Text(
                  '${payment['merchant']} · ${rupees(payment['amount'])}',
                ),
                subtitle: Text(
                  '${payment['transaction_date']} · ${payment['status']}\n${payment['linked_order'] == null ? 'Unlinked' : 'Linked to order ${payment['linked_order']}'}',
                ),
                trailing: IconButton(
                  tooltip: 'Link order',
                  icon: const Icon(Icons.link),
                  onPressed: () async {
                    final id = await _input(
                      context,
                      'Link a confirmed order',
                      'Enter the order ID from Order Details. Merchant and amount must match.',
                    );
                    if (id == null) return;
                    try {
                      await ref.read(apiProvider).post(
                        'payments/${payment['id']}/link-order/',
                        {'order': int.tryParse(id)},
                      );
                      if (mounted) setState(load);
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
              ),
            ),
          if ((result['results'] as List).isEmpty)
            const Text('No payment alerts imported.'),
        ],
      ),
    ),
  );
}
