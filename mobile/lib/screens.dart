import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:share_plus/share_plus.dart';
import 'api.dart';
import 'widgets.dart';
import 'receipt.dart';
import 'order_filters.dart';

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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(30),
          children: [
            const Icon(
              Icons.shopping_basket_rounded,
              size: 64,
              color: Color(0xff227c66),
            ),
            const SizedBox(height: 20),
            Text(
              'BasketWise',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'Every basket. A clearer picture.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            Text(
              register ? 'Create your account' : 'Welcome back',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email address'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              onSubmitted: (_) {
                if (!busy && (!register || consent)) submit();
              },
            ),
            if (register)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: consent,
                onChanged: (v) => setState(() => consent = v!),
                title: const Text(
                  'I consent to processing my uploaded receipts and accept the privacy policy.',
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy || (register && !consent) ? null : submit,
              child: Text(
                busy
                    ? 'Please wait…'
                    : register
                    ? 'Create account'
                    : 'Sign in',
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                register = !register;
                error = null;
              }),
              child: Text(
                register
                    ? 'Already have an account? Sign in'
                    : 'New here? Create an account',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ResetScreen()),
              ),
              child: const Text('Forgot password?'),
            ),
            TextButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const AlertDialog(
                  title: Text('Your privacy'),
                  content: SingleChildScrollView(
                    child: Text(
                      'BasketWise processes documents you choose to upload. Receipts remain private and are removed after the configured retention period (30 days by default). Saved order data remains until you delete it or your account. No SMS inbox access, merchant login or email syncing is enabled. Bank alerts retain only amount, date and merchant; account and VPA details are discarded. Export and delete your data from Profile. Production hosting must provide TLS and encrypted storage.',
                    ),
                  ),
                ),
              ),
              child: const Text('Privacy policy'),
            ),
          ],
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
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(revisionProvider, (_, _) => setState(load));
    return RemoteData(
      future: data,
      retry: () => setState(load),
      builder: (result) {
        final summary = result[0] as Json,
            recent = result[1]['results'] as List;
        return RefreshIndicator(
          onRefresh: () async {
            setState(load);
            await data;
          },
          child: PageBody(
            title: 'Your everyday,\nin perspective.',
            subtitle: 'BASKETWISE  /  SPENDING OVERVIEW',
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
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: const LinearGradient(
                    colors: [Color(0xff164e40), Color(0xff27826a)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'THIS MONTH · NET SPENDING',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        letterSpacing: 1.7,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      rupees(summary['this_month']['net_spending']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
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
                  final width = constraints.maxWidth < 600
                      ? (constraints.maxWidth - 14) / 2
                      : (constraints.maxWidth - 28) / 3;
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
                      _metric(
                        'Net in date range',
                        rupees(summary['net_spending']),
                        Icons.account_balance_wallet_outlined,
                        width,
                      ),
                    ],
                  );
                },
              ),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: SafeArea(child: ScanScreen())),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Import a receipt'),
              ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Across your baskets',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if ((summary['platforms'] as List).isEmpty)
                      const Text(
                        'Your platform breakdown appears after your first confirmed purchase.',
                      ),
                    for (final platform in summary['platforms'])
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(platform['label'].toString().toUpperCase()),
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
                      'Fees, made visible',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Delivery ${rupees(summary['delivery_fee'])}  ·  Handling ${rupees(summary['handling_fee'])}',
                    ),
                    Text(
                      '${summary['delivery_fee_unknown_count']} delivery and ${summary['handling_fee_unknown_count']} handling values unknown',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent orders',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (recent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'A little clarity starts with your first receipt. Upload, review, then save.',
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
              Icon(icon, size: 22),
              const SizedBox(height: 16),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(title),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              TextField(
                controller: search,
                decoration: InputDecoration(
                  labelText: 'Search products, platforms or order ID',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
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
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final result = await showDialog<Json>(
                      context: context,
                      builder: (context) => OrderFilters(initial: filters),
                    );
                    if (result != null && mounted) {
                      setState(() {
                        filters.clear();
                        filters.addAll(result);
                        page = 1;
                        load();
                      });
                    }
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Date, amount & source'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: platform,
                      decoration: const InputDecoration(labelText: 'Platform'),
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
                            child: Text(p.isEmpty ? 'All platforms' : p),
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
                            child: Text(s.isEmpty ? 'All statuses' : s),
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
            ],
          ),
        ),
        Expanded(
          child: RemoteData(
            future: data,
            retry: () => setState(load),
            builder: (result) => PageBody(
              title: 'Your orders',
              subtitle: '${result['count']} saved purchases',
              children: [
                if ((result['results'] as List).isEmpty)
                  const Panel(
                    child: Text(
                      'No matching orders. Try another search or import a receipt.',
                    ),
                  ),
                for (final order in result['results'])
                  Panel(
                    child: OrderTile(
                      order: Json.from(order),
                      onTap: () => context.push('/orders/${order['id']}'),
                    ),
                  ),
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
          ),
        ),
      ],
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
        title: 'Small baskets.\nBigger insights.',
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
                  const Text('Charts appear after a confirmed purchase.')
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
      title: 'A space for you.',
      subtitle: profile['email'],
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preferences',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: ref.watch(themeProvider),
                decoration: const InputDecoration(labelText: 'Appearance'),
                items: [
                  for (final theme in ['system', 'light', 'dark'])
                    DropdownMenuItem(value: theme, child: Text(theme)),
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
