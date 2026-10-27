import 'package:flutter/material.dart';

String platformLabel(String? slug) {
  return switch ((slug ?? 'other').toLowerCase()) {
    'instamart' => 'Instamart',
    'blinkit' => 'Blinkit',
    'zepto' => 'Zepto',
    'bigbasket' => 'BigBasket',
    _ => 'Other',
  };
}

String orderStatusLabel(String? status) {
  return switch ((status ?? 'unknown').toLowerCase()) {
    'delivered' => 'Delivered',
    'pending' => 'Pending',
    'cancelled' => 'Cancelled',
    'refunded' => 'Refunded',
    _ => 'Unknown',
  };
}

/// Shortcuts for manual product entry; names match analytics category labels.
const productCategories = <(String, IconData)>[
  ('Vegetables', Icons.eco_outlined),
  ('Fruits', Icons.apple),
  ('Dairy & eggs', Icons.egg_outlined),
  ('Snacks', Icons.cookie_outlined),
  ('Drinks', Icons.local_drink_outlined),
  ('Bakery', Icons.bakery_dining_outlined),
  ('Staples', Icons.rice_bowl_outlined),
  ('Meat & fish', Icons.set_meal_outlined),
  ('Household', Icons.cleaning_services_outlined),
  ('Personal care', Icons.spa_outlined),
];

abstract final class BasketStyle {
  static const ink = Color(0xff182c2b);
  static const green = Color(0xff176653);
  static const mint = Color(0xffe4f0e8);
  static const paper = Color(0xfff8f7f2);
  static const orange = Color(0xffd78346);

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: green,
      brightness: brightness,
      primary: dark ? const Color(0xff9bd3b9) : green,
      surface: dark ? const Color(0xff192a27) : Colors.white,
      onSurface: dark ? const Color(0xffe9efe8) : ink,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? const Color(0xff101e1b) : paper,
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontSize: 36,
          height: 1.12,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.6,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontSize: 30,
          height: 1.15,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xff101e1b) : paper,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff243630) : const Color(0xfff3f5f0),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .35)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 76,
        indicatorColor: dark ? const Color(0xff315447) : mint,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .5),
        space: 28,
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  final bool light;
  final bool compact;
  const BrandMark({super.key, this.light = false, this.compact = false});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 34 : 42,
        height: compact ? 34 : 42,
        decoration: BoxDecoration(
          color: light
              ? Colors.white.withValues(alpha: .14)
              : BasketStyle.green,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          Icons.shopping_basket_outlined,
          color: Colors.white,
          size: compact ? 21 : 25,
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'basketwise',
        style: TextStyle(
          color: light ? Colors.white : Theme.of(context).colorScheme.onSurface,
          fontSize: compact ? 20 : 24,
          letterSpacing: -.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const Eyebrow(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.7,
      color: color ?? Theme.of(context).colorScheme.primary,
    ),
  );
}

class SoftNotice extends StatelessWidget {
  final IconData icon;
  final String title, text;
  const SoftNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: .32),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(text, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

class FlowStatus extends StatelessWidget {
  final bool loading;
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;
  const FlowStatus({
    super.key,
    this.loading = false,
    required this.icon,
    required this.title,
    required this.message,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: CircularProgressIndicator(),
            )
          else
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                icon,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 24),
            ...actions.expand((action) => [action, const SizedBox(height: 10)]),
          ],
        ],
      ),
    ),
  );
}

class ReceiptHero extends StatelessWidget {
  const ReceiptHero({super.key});
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    padding: const EdgeInsets.fromLTRB(22, 23, 16, 23),
    decoration: BoxDecoration(
      color: BasketStyle.green,
      borderRadius: BorderRadius.circular(26),
    ),
    child: Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('LESS GUESSWORK.', color: Color(0xffb9dcc7)),
              SizedBox(height: 9),
              Text(
                'More clarity.\nEvery basket.',
                style: TextStyle(
                  fontSize: 27,
                  height: 1.15,
                  letterSpacing: -.9,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 15),
              Text(
                'Keep the receipt.\nSee the bigger picture.',
                style: TextStyle(
                  color: Color(0xffd2e9dc),
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        Transform.rotate(
          angle: .11,
          child: Container(
            width: 106,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: BasketStyle.paper,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .13),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.shopping_basket_outlined,
                  color: BasketStyle.green,
                  size: 25,
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xffd4ddd4),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 14,
                          height: 4,
                          color: const Color(0xffd4ddd4),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 13, color: Color(0xffd4ddd4)),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 8,
                        color: BasketStyle.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      Icons.check_circle_rounded,
                      color: BasketStyle.green,
                      size: 17,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
