import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:basketwise/api.dart';
import 'package:basketwise/receipt.dart';
import 'package:basketwise/main.dart' as app;

void main() {
  const live = bool.fromEnvironment('LIVE_API');
  testWidgets(
    'Live PDF upload, review correction, confirm and Flutter dashboard',
    (tester) async {
      HttpOverrides.global = null;
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues(
        {},
      ); // OS keychain only; HTTP/OCR/database are real.
      await tester.runAsync(() async {
        final fontPath = Platform.environment['BASKETWISE_TEST_FONT'];
        if (fontPath != null) {
          await (FontLoader('Roboto')..addFont(
                Future.value(
                  ByteData.sublistView(await File(fontPath).readAsBytes()),
                ),
              ))
              .load();
        }
        final iconPath = Platform.environment['BASKETWISE_TEST_ICONS'];
        if (iconPath != null) {
          await (FontLoader('MaterialIcons')..addFont(
                Future.value(
                  ByteData.sublistView(await File(iconPath).readAsBytes()),
                ),
              ))
              .load();
        }
        final api = Api();
        const password = 'Integration-test-only-9821!';
        await api.authenticate(
          'flutter-${DateTime.now().microsecondsSinceEpoch}@example.test',
          password,
          true,
        );
        try {
          final file = File(
            '../backend/tests/fixtures/instamart.synthetic.pdf',
          );
          api.access =
              'expired-test-access-token'; // Exercise real refresh + multipart replay.
          final upload = await api.upload(
            await file.readAsBytes(),
            'instamart.synthetic.pdf',
            (_) {},
          );
          final id = upload['id'];
          Json? preview;
          for (var i = 0; i < 40; i++) {
            final result = await api.get('receipts/$id/preview/');
            if (result['status'] == 'review') {
              preview = Json.from(result['data']);
              break;
            }
            if (result['status'] == 'failed') throw StateError(result['error']);
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          expect(preview, isNotNull);
          expect(preview!['grand_total'], '286.00');
          final saved = Completer<void>();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OrderEditor(
                  initial: preview,
                  submitLabel: 'Confirm and save',
                  onSave: (values) async {
                    try {
                      await api.post('receipts/$id/confirm/', {
                        ...values,
                        'reviewed': true,
                        'acknowledge_warnings': true,
                      });
                      saved.complete();
                    } catch (error) {
                      saved.completeError(error);
                      rethrow;
                    }
                  },
                ),
              ),
            ),
          );
          await tester.ensureVisible(
            find.widgetWithText(TextFormField, 'Order Date'),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Order Date'),
            DateTime.now().toIso8601String().substring(0, 10),
          );
          tester.testTextInput.hide();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Confirm and save'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Confirm and save'));
          await tester.pumpAndSettle();
          expect(find.text('Save reviewed purchase?'), findsOneWidget);
          await tester.tap(find.text('Continue'));
          await tester.pump();
          await saved.future.timeout(const Duration(seconds: 20));
          await tester.pumpWidget(
            ProviderScope(
              overrides: [apiProvider.overrideWithValue(api)],
              child: const app.BasketWiseApp(),
            ),
          );
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            if (find.text('₹286.00').evaluate().isNotEmpty) break;
          }
          expect(find.text('₹286.00'), findsWidgets);
          expect(find.text('INSTAMART'), findsWidgets);
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../.runtime/dashboard.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          await api.delete('account/', data: {'password': password});
        }
      });
    },
    skip: !live,
  );
}
