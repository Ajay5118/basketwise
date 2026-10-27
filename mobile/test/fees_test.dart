import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketwise/design.dart';
import 'package:basketwise/fees.dart';

const sample = {
  'this_month': {
    'fees': '121.99',
    'order_count': 3,
    'fees_unknown_count': 1,
    'comparable_items': '500.00',
    'fee_share_percent': '24.4',
  },
  'last_month': {
    'fees': '30.00',
    'order_count': 1,
    'fees_unknown_count': 0,
    'comparable_items': '500.00',
    'fee_share_percent': '6.0',
  },
  'all_time': {
    'fees': '151.99',
    'order_count': 4,
    'fees_unknown_count': 1,
    'comparable_items': '1000.00',
    'fee_share_percent': '15.2',
  },
  'by_type': [
    {
      'key': 'other_fees',
      'label': 'Small cart, surge & other',
      'amount': '75.00',
      'order_count': 1,
    },
    {
      'key': 'delivery_fee',
      'label': 'Delivery',
      'amount': '57.00',
      'order_count': 3,
    },
  ],
  'by_platform': [
    {
      'platform': 'zepto',
      'fees': '141.99',
      'orders': 2,
      'average_fee': '71.00',
    },
    {
      'platform': 'blinkit',
      'fees': '10.00',
      'orders': 1,
      'average_fee': '10.00',
    },
  ],
  'monthly': [
    {'label': '2026-09', 'amount': '30.00'},
    {'label': '2026-10', 'amount': '121.99'},
  ],
  'heavy_baskets': {'count': 1, 'fees': '111.99', 'items': '60.00'},
  'worst_order': {
    'id': 7,
    'order_date': '2026-10-05',
    'platform': 'zepto',
    'fees': '111.99',
    'items': '60.00',
  },
};

void main() {
  test(
    'Fee share reads as rupees per hundred and stays unknown when absent',
    () {
      expect(
        perHundredText({'fee_share_percent': '24.4'}),
        '₹24 extra on every ₹100 of groceries',
      );
      expect(perHundredText({'fee_share_percent': null}), isNull);
    },
  );

  test('Nudges come only from stated fees, strongest first', () {
    final nudges = feeNudges(Map<String, dynamic>.from(sample));
    expect(nudges, hasLength(3));
    expect(nudges[0], contains('1 basket cost ₹111.99 in fees on just ₹60.00'));
    expect(nudges[1], contains('Zepto charges you ₹71.00 per order'));
    expect(
      nudges[2],
      startsWith('Small cart, surge & other is your biggest fee'),
    );
    expect(
      feeNudges({
        'heavy_baskets': {'count': 0},
        'by_platform': [],
        'by_type': [],
      }),
      isEmpty,
    );
  });

  testWidgets('Fee insights fit a narrow phone and explain the numbers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: BasketStyle.theme(Brightness.light),
        home: Scaffold(
          body: FeeInsightsView(data: Map<String, dynamic>.from(sample)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('₹121.99'), findsWidgets);
    expect(find.text('₹24 extra on every ₹100 of groceries'), findsOneWidget);
    expect(find.text('1 order has no fee details yet'), findsOneWidget);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Your priciest convenience'),
      300,
      scrollable: scrollable,
    );
    await tester.scrollUntilVisible(
      find.text('Fees by month'),
      300,
      scrollable: scrollable,
    );
    expect(find.text('October 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('No recorded fees shows guidance instead of zeros', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeeInsightsView(
            data: {
              ...sample,
              'by_type': <Map>[],
              'by_platform': <Map>[],
              'monthly': <Map>[],
            },
          ),
        ),
      ),
    );
    expect(find.text('No fees recorded yet'), findsOneWidget);
  });
}
