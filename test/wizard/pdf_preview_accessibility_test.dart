// Real printing5.13.4 actions; the platform boundary is recorded, not raster
// parity or Android proof. Native instrumentation separately verifies this UI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:writing_questions_app/views/widgets/pdf_preview_screen.dart';

class _RecordedPrinting {
  _RecordedPrinting(this.messenger, {this.enabled = true});
  final TestDefaultBinaryMessenger messenger;
  final bool enabled;
  static const channel = MethodChannel('net.nfet.printing');
  final shares = <Uint8List>[];
  final prints = <Uint8List>[];
  final names = <String>[];
  final shareBounds = <Rect>[];

  Future<ByteData?> _incoming(String method, Map<dynamic, dynamic> arguments) =>
      messenger.handlePlatformMessage(channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)), null);

  void install() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map<dynamic, dynamic>;
      switch (call.method) {
        case 'printingInfo':
          return <String, bool>{'canPrint': enabled, 'canShare': enabled,
            'canRaster': true, 'canConvertHtml': false};
        case 'rasterPdf':
          await _incoming('onPageRasterEnd', {'job': args['job']});
          return null;
        case 'sharePdf':
          shares.add(args['doc'] as Uint8List);
          names.add(args['name'] as String);
          shareBounds.add(Rect.fromLTWH(args['x'] as double, args['y'] as double,
            args['w'] as double, args['h'] as double));
          return 1;
        case 'printPdf':
          final response = await _incoming('onLayout', args);
          prints.add(channel.codec.decodeEnvelope(response!) as Uint8List);
          names.add(args['name'] as String);
          await _incoming('onCompleted', {'job': args['job'], 'completed': true});
          return 1;
        default:
          throw StateError('Unexpected real printing platform call: ${call.method}');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }
}

void main() {
  for (final width in [320.0, 360.0]) {
    testWidgets('PDF actions have native names, disjoint48dp corner targets and identical bytes at $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = _RecordedPrinting(tester.binding.defaultBinaryMessenger)..install();
      final document = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('Unchanged PDF bytes')));
      final bytes = await document.save();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MaterialApp(home: PdfPreviewScreen(pdfBytes: bytes,
          title: 'PDF', fileName: 'mixed-Arabic-123.pdf')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final rectangles = <Rect>[];
        for (final label in ['طباعة PDF', 'مشاركة PDF']) {
          // Tooltip wraps the real package action, not a replacement callback.
          final action = label == 'طباعة PDF' ? find.byType(PdfPrintAction) : find.byType(PdfShareAction);
          expect(action, findsOneWidget);
          final target = find.descendant(of: action, matching: find.byType(IconButton));
          expect(target, findsOneWidget);
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(800));
          expect(tester.getSemantics(target).label, contains(label));
          rectangles.add(rect);
          for (final point in [rect.topLeft + const Offset(1, 1), rect.topRight + const Offset(-1, 1),
            rect.bottomLeft + const Offset(1, -1), rect.bottomRight - const Offset(1, 1)]) {
            await tester.tapAt(point);
            await tester.pump();
          }
        }
        var expectedZoom = 1.0;
        for (final label in ['تصغير المعاينة', 'تكبير المعاينة', 'إعادة الحجم الأصلي']) {
          // IconButton's internal Tooltip may wrap only the24dp icon; measure
          // the real receiving button, then prove all four corner hits act.
          final target = find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == label);
          expect(target, findsOneWidget);
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(800));
          for (final previous in rectangles) {
            expect(previous.overlaps(rect), isFalse, reason: '$label must not overlap another PDF target.');
          }
          rectangles.add(rect);
          for (final point in [rect.topLeft + const Offset(1, 1), rect.topRight + const Offset(-1, 1),
            rect.bottomLeft + const Offset(1, -1), rect.bottomRight - const Offset(1, 1)]) {
            await tester.tapAt(point);
            await tester.pump();
            expectedZoom = label == 'إعادة الحجم الأصلي' ? 1.0
                : (expectedZoom + (label == 'تصغير المعاينة' ? -0.25 : 0.25)).clamp(0.6, 4.0).toDouble();
            expect(find.text('${(expectedZoom * 100).round()}%'), findsOneWidget,
              reason: 'The actual $label corner must change/reset zoom, not just appear in a hit path.');
          }
        }
        expect(find.text('100%'), findsOneWidget);
        expect(rectangles[0].overlaps(rectangles[1]), isFalse);
        expect(platform.shares, hasLength(4));
        expect(platform.prints, hasLength(4));
        for (final output in [...platform.shares, ...platform.prints]) {
          expect(output, orderedEquals(bytes));
        }
        expect(platform.names, everyElement('mixed-Arabic-123.pdf'));
        expect(platform.shareBounds, everyElement(rectangles[1]));
        expect(tester.takeException(), isNull);
      } finally {
        // Flutter verifies live SemanticsHandles before addTearDown runs.
        semantics.dispose();
      }
    });
  }

  testWidgets('unavailable platform retains capability-gated actions', (tester) async {
    _RecordedPrinting(tester.binding.defaultBinaryMessenger, enabled: false).install();
    await tester.pumpWidget(MaterialApp(home: PdfPreviewScreen(pdfBytes: Uint8List(0), title: 'PDF', fileName: 'empty.pdf')));
    await tester.pump();
    expect(find.byType(PdfPrintAction), findsNothing);
    expect(find.byType(PdfShareAction), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
