import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';
import 'design.dart';

String rupees(dynamic amount) => amount == null
    ? 'Unknown'
    : NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(num.tryParse(amount.toString()) ?? 0);

class PageBody extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  final Widget? action;
  final bool showBranding;
  const PageBody({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
    this.showBranding = true,
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showBranding) ...[const BrandMark(compact: true), const SizedBox(height: 28)],
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('YOUR EVERYDAY, UNDERSTOOD'),
                  const SizedBox(height: 9),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 28),
        ...children.expand((child) => [child, const SizedBox(height: 18)]),
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  const Panel({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class RemoteData extends StatelessWidget {
  final Future<dynamic> future;
  final Widget Function(dynamic) builder;
  final VoidCallback? retry;
  const RemoteData({
    super.key,
    required this.future,
    required this.builder,
    this.retry,
  });
  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 16),
                Text(errorText(snapshot.error!)),
                if (retry != null)
                  TextButton(onPressed: retry, child: const Text('Try again')),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading…'),
            ],
          ),
        );
      }
      return builder(snapshot.data);
    },
  );
}

class OrderTile extends StatelessWidget {
  final Json order;
  final VoidCallback onTap;
  const OrderTile({super.key, required this.order, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final platform = (order['platform'] ?? 'other').toString();
    final label = platformLabel(platform);
    final color = switch (platform) {
      'zepto' => const Color(0xff7754a8),
      'blinkit' => const Color(0xff9a7a19),
      'instamart' => const Color(0xffc46632),
      _ => BasketStyle.green,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(Icons.shopping_bag_outlined, color: color, size: 23),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order['order_date']} · ${(order['items'] as List? ?? []).length} items',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    orderStatusLabel(order['status']?.toString()),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                rupees(order['grand_total']),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

void showError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorText(error)),
        duration: const Duration(seconds: 7),
      ),
    );

Future<bool> approve(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(title),
        content: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, save'),
          ),
        ],
      ),
    ) ??
    false;
