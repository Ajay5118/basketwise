import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'api.dart';
import 'design.dart';
import 'widgets.dart';

num _amount(dynamic value) => num.tryParse('${value ?? ''}') ?? 0;

/// "₹24 extra on every ₹100 of groceries" reads easier than a percentage.
String? perHundredText(Json summary) {
  final share = num.tryParse('${summary['fee_share_percent'] ?? ''}');
  if (share == null) return null;
  return '₹${share.round()} extra on every ₹100 of groceries';
}

String _shortDate(String? iso) {
  final parsed = DateTime.tryParse(iso ?? '');
  return parsed == null ? '' : DateFormat('d MMM').format(parsed);
}

/// Plain-language observations, strongest first. Only facts from stated fees.
List<String> feeNudges(Json data) {
  final nudges = <String>[];
  final heavy = data['heavy_baskets'] as Map? ?? {};
  if (_amount(heavy['count']) > 0) {
    final count = heavy['count'];
    nudges.add(
      '$count ${count == 1 ? 'basket' : 'baskets'} cost ${rupees(heavy['fees'])} in fees on just ${rupees(heavy['items'])} of items. Fewer, fuller orders are the easiest saving.',
    );
  }
  final platforms = (data['by_platform'] as List? ?? []).cast<Map>();
  if (platforms.length >= 2) {
    final high = platforms.first, low = platforms.last;
    nudges.add(
      '${platformLabel(high['platform'])} charges you ${rupees(high['average_fee'])} per order in fees; ${platformLabel(low['platform'])} ${rupees(low['average_fee'])}.',
    );
  }
  final types = (data['by_type'] as List? ?? []).cast<Map>();
  if (types.isNotEmpty && _amount(types.first['amount']) > 0) {
    nudges.add(
      '${types.first['label']} is your biggest fee: ${rupees(types.first['amount'])} across ${types.first['order_count']} ${types.first['order_count'] == 1 ? 'order' : 'orders'}.',
    );
  }
  return nudges;
}

/// Home card: this month's convenience cost, linking to the full breakdown.
class FeeHighlight extends StatelessWidget {
  final Json data;
  final VoidCallback? onTap;
  const FeeHighlight({super.key, required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    final month = Json.from(data['this_month'] as Map);
    final perHundred = perHundredText(month);
    final unknown = _amount(month['fees_unknown_count']);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: BasketStyle.orange.withValues(alpha: .12),
          border: Border.all(color: BasketStyle.orange.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Eyebrow(
                    'The cost of convenience',
                    color: BasketStyle.orange,
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 19,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                rupees(month['fees']),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ),
            const Text('in delivery, handling and extra fees this month'),
            if (perHundred != null) ...[
              const SizedBox(height: 8),
              Text(
                perHundred,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (unknown > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${unknown.toInt()} ${unknown == 1 ? 'order has' : 'orders have'} no fee details yet',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FeeInsightsScreen extends ConsumerStatefulWidget {
  const FeeInsightsScreen({super.key});
  @override
  ConsumerState<FeeInsightsScreen> createState() => _FeeInsightsScreenState();
}

class _FeeInsightsScreenState extends ConsumerState<FeeInsightsScreen> {
  late Future<dynamic> data;

  @override
  void initState() {
    super.initState();
    data = ref.read(apiProvider).get('analytics/fees/');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fee insights')),
    body: RemoteData(
      future: data,
      retry: () =>
          setState(() => data = ref.read(apiProvider).get('analytics/fees/')),
      builder: (result) => FeeInsightsView(data: Json.from(result as Map)),
    ),
  );
}

class FeeInsightsView extends StatelessWidget {
  final Json data;
  const FeeInsightsView({super.key, required this.data});

  Widget _bars(
    BuildContext context,
    List<Map> rows,
    String Function(Map) label,
    String Function(Map) value,
    num Function(Map) amount,
  ) {
    final largest = rows.map(amount).fold<num>(0, (a, b) => b > a ? b : a);
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(label(row))),
                    Text(
                      value(row),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: largest > 0 ? amount(row) / largest : 0,
                    minHeight: 8,
                    color: BasketStyle.orange,
                    backgroundColor: BasketStyle.orange.withValues(alpha: .12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final month = Json.from(data['this_month'] as Map);
    final last = Json.from(data['last_month'] as Map);
    final allTime = Json.from(data['all_time'] as Map);
    final types = (data['by_type'] as List).cast<Map>();
    final platforms = (data['by_platform'] as List).cast<Map>();
    final monthly = (data['monthly'] as List).cast<Map>();
    final worst = data['worst_order'] as Map?;
    final nudges = feeNudges(data);
    final perHundred = perHundredText(month) ?? perHundredText(allTime);
    final title = Theme.of(context).textTheme.titleLarge;
    if (types.isEmpty) {
      return PageBody(
        showBranding: false,
        title: 'What convenience\ncosts you.',
        subtitle: 'Delivery, handling and extra fees across every app.',
        children: const [
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No fees recorded yet',
            message:
                'Save receipts or bill summaries that show delivery, handling or small cart fees, and they will add up here.',
          ),
        ],
      );
    }
    return PageBody(
      showBranding: false,
      title: 'What convenience\ncosts you.',
      subtitle: 'Delivery, handling and extra fees across every app.',
      children: [
        FeeHighlight(data: data),
        Text(
          'Last month ${rupees(last['fees'])} · All time ${rupees(allTime['fees'])} across ${allTime['order_count']} orders',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (perHundred != null && perHundredText(month) == null)
          SoftNotice(
            icon: Icons.insights_outlined,
            title: 'All time',
            text: perHundred,
          ),
        for (final nudge in nudges)
          SoftNotice(
            icon: Icons.lightbulb_outline,
            title: 'Worth knowing',
            text: nudge,
          ),
        if (worst != null)
          Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.local_fire_department_outlined,
                color: BasketStyle.orange,
              ),
              title: const Text('Your priciest convenience'),
              subtitle: Text(
                '${rupees(worst['fees'])} in fees on ${rupees(worst['items'])} of items · ${platformLabel(worst['platform'])}, ${_shortDate(worst['order_date'])}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/orders/${worst['id']}'),
            ),
          ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Where the fees go', style: title),
              const SizedBox(height: 8),
              _bars(
                context,
                types,
                (row) => '${row['label']}',
                (row) => rupees(row['amount']),
                (row) => _amount(row['amount']),
              ),
            ],
          ),
        ),
        if (platforms.isNotEmpty)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Average fee per order', style: title),
                const SizedBox(height: 8),
                _bars(
                  context,
                  platforms,
                  (row) =>
                      '${platformLabel(row['platform'])} · ${row['orders']} ${row['orders'] == 1 ? 'order' : 'orders'}',
                  (row) => rupees(row['average_fee']),
                  (row) => _amount(row['average_fee']),
                ),
              ],
            ),
          ),
        if (monthly.length > 1)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fees by month', style: title),
                const SizedBox(height: 8),
                _bars(
                  context,
                  monthly,
                  (row) {
                    final parsed = DateTime.tryParse('${row['label']}-01');
                    return parsed == null
                        ? '${row['label']}'
                        : DateFormat('MMMM y').format(parsed);
                  },
                  (row) => rupees(row['amount']),
                  (row) => _amount(row['amount']),
                ),
              ],
            ),
          ),
        Text(
          'Fees count only when your receipt states them. The ₹-per-₹100 figure uses orders where both fees and item value are known. Taxes and discounts are not counted as fees.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
