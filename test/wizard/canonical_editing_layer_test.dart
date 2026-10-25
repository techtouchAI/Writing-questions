import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/canonical/layout_units.dart';
import 'package:writing_questions_app/views/wizard/canonical_editing_layer.dart';

// These are placement/IME component tests, NOT production-editor acceptance.
// Integration must supply the actual plan, existing handlers and source fields
// before the default production surface may be switched.
const _anchor = LayoutRect.fromLTWH(375, 300, 150, 18);

class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final viewport = GlobalKey();
  final pages = <GlobalKey>[GlobalKey(), GlobalKey()];
  final vertical = ScrollController();
  final horizontal = ScrollController();
  final field = TextEditingController();
  final focus = FocusNode();
  late final Listenable scrollChanges = Listenable.merge(<Listenable>[vertical, horizontal]);
  var visible = false;
  var zoom = 0.4;
  var pageIndex = 0;

  void change({bool? show, double? scale, int? page}) => setState(() {
        visible = show ?? visible;
        zoom = scale ?? zoom;
        pageIndex = page ?? pageIndex;
      });

  @override
  void dispose() {
    vertical.dispose();
    horizontal.dispose();
    field.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(builder: (context, constraints) => Stack(
            key: viewport,
            children: <Widget>[
              SingleChildScrollView(
                controller: vertical,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SingleChildScrollView(
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(constraints.maxWidth, 794 * zoom + 24),
                    child: Column(children: <Widget>[
                      for (final key in pages)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          width: 794 * zoom,
                          height: 1122 * zoom,
                          child: FittedBox(
                            fit: BoxFit.fill,
                            child: RepaintBoundary(
                              child: SizedBox(
                                key: key,
                                width: 794,
                                height: 1122,
                                child: const ColoredBox(color: Colors.white,
                                    child: Align(alignment: Alignment.topLeft,
                                      child: Text('Printed content does not depend on selection.'))),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 1000),
                    ]),
                  ),
                ),
              ),
              if (visible)
                Positioned.fill(child: CanonicalEditingLayer(
                  viewportKey: viewport,
                  pageKey: pages[pageIndex],
                  anchorPt: _anchor,
                  scrollChanges: scrollChanges,
                  child: Material(elevation: 8, child: SizedBox(
                    key: const ValueKey<String>('native-editor'),
                    height: 180,
                    child: TextField(controller: field, focusNode: focus, autofocus: true),
                  )),
                )),
            ],
          )),
        ),
      );
}

void _expectAnchor(WidgetTester tester, _HarnessState state) {
  final viewport = state.viewport.currentContext!.findRenderObject()! as RenderBox;
  final page = state.pages[state.pageIndex].currentContext!.findRenderObject()! as RenderBox;
  final anchor = MatrixUtils.transformRect(page.getTransformTo(viewport), Rect.fromLTWH(
    LayoutUnits.ptToPx(_anchor.left), LayoutUnits.ptToPx(_anchor.top),
    LayoutUnits.ptToPx(_anchor.width), LayoutUnits.ptToPx(_anchor.height),
  ));
  final actual = tester.getRect(find.byKey(const ValueKey<String>('native-editor')))
      .shift(-viewport.localToGlobal(Offset.zero));
  final below = anchor.bottom + 8;
  final top = below + actual.height <= viewport.size.height - 8
      ? below : anchor.top - actual.height - 8;
  expect(actual.left, closeTo((anchor.right - actual.width)
      .clamp(8.0, viewport.size.width - 8 - actual.width), 1e-6));
  expect(actual.top, closeTo(top.clamp(8.0, viewport.size.height - 8 - actual.height), 1e-6));
  expect(actual.width, closeTo(math.min(560.0, viewport.size.width - 16), 1e-6));
  expect(actual.height, 180);
}

void main() {
  for (final width in <double>[320, 360]) {
    testWidgets('native editor follows real page transform without moving paper at $width dp',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: key));
      final state = key.currentState!;
      final before = tester.getRect(find.byKey(state.pages.first));
      state.change(show: true);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(state.pages.first)), before);
      _expectAnchor(tester, state);
      state.vertical.jumpTo(100);
      await tester.pumpAndSettle();
      _expectAnchor(tester, state);
      state.change(scale: 1);
      await tester.pumpAndSettle();
      _expectAnchor(tester, state);
      state.horizontal.jumpTo(100);
      await tester.pumpAndSettle();
      _expectAnchor(tester, state);
      state.change(show: false);
      await tester.pumpAndSettle();
      state.vertical.jumpTo(0);
      state.horizontal.jumpTo(0);
      state.change(scale: 0.4);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(state.pages.first)), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changing continuation anchor and zoom keeps focus and IME composing range',
      (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    final state = key.currentState!;
    state.change(show: true);
    await tester.pumpAndSettle();
    const editing = TextEditingValue(text: 'مصدر واحد',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4));
    tester.testTextInput.updateEditingValue(editing);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    state.change(page: 1, scale: 1);
    await tester.pumpAndSettle();
    expect(tester.state<EditableTextState>(find.byType(EditableText)), same(editable));
    expect(state.focus.hasFocus, isTrue);
    expect(state.field.value, editing);
    _expectAnchor(tester, state);
    expect(tester.takeException(), isNull);
  });
}
