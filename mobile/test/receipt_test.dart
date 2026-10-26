import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketwise/receipt.dart';
import 'package:basketwise/widgets.dart';

void main() {
  test('Indian currency and unknown presentation', () {
    expect(rupees('123456.50'), '₹1,23,456.50');
    expect(rupees(null), 'Unknown');
  });
  testWidgets('Review requires date and explicit verification before saving', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderEditor(
            initial: {
              'platform': 'instamart',
              'status': 'delivered',
              'grand_total': '286.00',
              'items': [
                {
                  'name': 'Heritage Pouch Curd',
                  'quantity': '2',
                  'unit_price': '47.00',
                  'unit_price_derived': true,
                  'line_total': '94.00',
                  'category': 'Uncategorized',
                },
              ],
            },
            submitLabel: 'Confirm and save',
            onSave: (_) async {
              saved = true;
            },
          ),
        ),
      ),
    );
    expect(find.text('Check the details.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Confirm and save'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm and save'),
    );
    expect(button.onPressed, isNull);
    expect(saved, isFalse);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Confirm and save'));
    await tester.pump();
    expect(saved, isFalse);
    await tester.scrollUntilVisible(
      find.text('Order Date'),
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enter a valid date as YYYY-MM-DD'), findsOneWidget);
  });
}
