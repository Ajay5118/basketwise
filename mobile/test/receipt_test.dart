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
    expect(find.text('Quick review'), findsOneWidget);
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
      find.text('Purchase date'),
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enter a valid date as YYYY-MM-DD'), findsOneWidget);
  });
  testWidgets(
    'Bill summary without products: quick add a category and keep other fees',
    (tester) async {
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderEditor(
              initial: {
                'platform': 'other',
                'grand_total': '192.49',
                'other_fees': '45.00',
                'items': [],
              },
              submitLabel: 'Confirm and save',
              onSave: (data) async {
                saved = data;
              },
            ),
          ),
        ),
      );
      final scrollable = find.byType(Scrollable).first;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Purchase date'),
        '2026-10-01',
      );
      final snacks = find.widgetWithText(ActionChip, 'Snacks');
      await tester.scrollUntilVisible(snacks, 200, scrollable: scrollable);
      await tester.tap(snacks);
      await tester.pump();
      expect(find.widgetWithText(TextFormField, 'Snacks'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Snacks'))
            .selected,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        300,
        scrollable: scrollable,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Confirm and save'),
        200,
        scrollable: scrollable,
      );
      await tester.tap(find.text('Confirm and save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, save'));
      await tester.pumpAndSettle();
      expect(saved?['other_fees'], '45.00');
      expect(saved?['grand_total'], '192.49');
      final item = (saved?['items'] as List).single as Map;
      expect(item['name'], 'Snacks');
      expect(item['category'], 'Snacks');
      expect(item['quantity'], '1');
    },
  );
}
