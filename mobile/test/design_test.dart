import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:basketwise/api.dart';
import 'package:basketwise/design.dart';
import 'package:basketwise/main.dart';
import 'package:basketwise/receipt.dart';
import 'package:basketwise/screens.dart';

class DesignApi extends Api {
  @override
  Future<dynamic> get(String path, {Json? query}) async {
    if (path == 'analytics/overview/') {
      return {
        'this_month': {'net_spending': '0.00'},
        'last_month': {'net_spending': '0.00'},
        'change_percent': null,
        'order_count': 0,
        'average_order_value': null,
        'net_spending': '0.00',
        'delivery_fee': '0.00',
        'handling_fee': '0.00',
        'delivery_fee_unknown_count': 0,
        'handling_fee_unknown_count': 0,
        'platforms': [],
      };
    }
    if (path == 'analytics/fees/') {
      const empty = {
        'fees': '0.00',
        'order_count': 0,
        'fees_unknown_count': 0,
        'comparable_items': '0.00',
        'fee_share_percent': null,
      };
      return {
        'this_month': empty,
        'last_month': empty,
        'all_time': empty,
        'by_type': [],
        'by_platform': [],
        'monthly': [],
        'heavy_baskets': {'count': 0, 'fees': '0.00', 'items': '0.00'},
        'worst_order': null,
      };
    }
    if (path == 'receipts/9/preview/') {
      return {
        'id': 9,
        'status': 'review',
        'data': {'items': [], 'grand_total': null},
      };
    }
    return {'results': [], 'count': 0, 'next': null};
  }
}

Future<void> loadPreviewFonts() async {
  for (final pair in [
    ('Roboto', 'BASKETWISE_TEST_FONT'),
    ('MaterialIcons', 'BASKETWISE_TEST_ICONS'),
  ]) {
    var path = Platform.environment[pair.$2];
    if (path == null) {
      var directory = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 8; i++) {
        final candidate = File(
          '${directory.path}/artifacts/material_fonts/${pair.$1 == 'Roboto' ? 'roboto-regular.ttf' : 'materialicons-regular.otf'}',
        );
        if (await candidate.exists()) {
          path = candidate.path;
          break;
        }
        directory = directory.parent;
      }
    }
    if (path != null) {
      await (FontLoader(pair.$1)..addFont(
            Future.value(ByteData.sublistView(await File(path).readAsBytes())),
          ))
          .load();
    }
  }
}

Future<void> screenshot(WidgetTester tester, String name) async {
  if (Platform.environment['BASKETWISE_SCREENSHOTS'] != '1') return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final snapshot = await boundary.toImage(pixelRatio: 2);
    final bytes = await snapshot.toByteData(format: ui.ImageByteFormat.png);
    final output = File('../.runtime/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List());
    snapshot.dispose();
  });
}

Widget preview(Widget child) => ProviderScope(
  overrides: [apiProvider.overrideWithValue(DesignApi())],
  child: MaterialApp(
    theme: BasketStyle.theme(Brightness.light),
    home: RepaintBoundary(child: child),
  ),
);

void main() {
  testWidgets('Login stays usable on a narrow screen with the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadPreviewFonts);
    await tester.pumpWidget(preview(const AuthScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'login-redesign');
    await tester.tap(find.byType(TextField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Sign in'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Dashboard keeps balanced metrics and navigation at phone width',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(loadPreviewFonts);
      await tester.pumpWidget(preview(const AppShell()));
      await tester.pumpAndSettle();
      expect(find.text('Import a receipt'), findsOneWidget);
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('THE COST OF CONVENIENCE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'dashboard-redesign');
    },
  );

  testWidgets('Empty extraction explains what happened before manual entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadPreviewFonts);
    await tester.pumpWidget(preview(const ReviewScreen(id: '9')));
    await tester.pumpAndSettle();
    expect(find.text('Your upload arrived safely'), findsOneWidget);
    expect(find.text('Enter details manually'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await screenshot(tester, 'review-empty-redesign');
    await tester.ensureVisible(find.text('Enter details manually'));
    await tester.tap(find.text('Enter details manually'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scan upload actions stay usable at narrow phone width', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(loadPreviewFonts);
    await tester.pumpWidget(
      preview(const Scaffold(body: SafeArea(child: ScanScreen()))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose receipts'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'scan-redesign');
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  test('Authentication and upload timeouts give appropriate advice', () {
    DioException failure(
      String path, {
      int? status,
      dynamic body,
      DioExceptionType type = DioExceptionType.badResponse,
    }) {
      final request = RequestOptions(path: path);
      return DioException(
        requestOptions: request,
        response: status == null
            ? null
            : Response(requestOptions: request, statusCode: status, data: body),
        type: type,
      );
    }

    expect(
      errorText(failure('auth/login/', status: 401)),
      contains('email or password'),
    );
    expect(
      errorText(failure('orders/', status: 401)),
      contains('session has expired'),
    );
    expect(
      errorText(failure('auth/login/', type: DioExceptionType.receiveTimeout)),
      isNot(contains('receipt')),
    );
    expect(
      errorText(
        failure('receipts/upload/', type: DioExceptionType.receiveTimeout),
      ),
      contains('Refresh before uploading again'),
    );
    expect(
      errorText(
        failure(
          'auth/register/',
          status: 400,
          body: {
            'password': ['Too short.'],
          },
        ),
      ),
      'password: Too short.',
    );
  });
}
