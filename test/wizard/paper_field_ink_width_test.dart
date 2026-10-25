import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/models/paper_font.dart';
import 'package:writing_questions_app/views/widgets/paper_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(FlutterTextMetrics.ensureFontsLoaded);

  testWidgets('printed ink keeps its width without hiding the native caret', (tester) async {
    const text = 'Alpha Beta';
    final style = TextStyle(
      fontFamily: PaperFont.naskh.family,
      fontSize: 14,
      height: 1.8,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      wordSpacing: 0,
      color: Colors.black,
    );
    final measurement = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    // The real phrase fits the printed column. Deducting the native caret's
    // 3px gutter makes it wrap: no font-dependent guessed width or tolerance.
    final width = measurement.width + 1;
    measurement.dispose();
    final controllers = <TextEditingController>[
      TextEditingController(text: text),
      TextEditingController(text: text),
    ];
    addTearDown(() { for (final controller in controllers) { controller.dispose(); } });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < 2; i++)
          SizedBox(width: width, child: PaperField(
            key: ValueKey<String>('ink-$i'),
            controller: controllers[i],
            style: style,
            matchPrintedTextWidth: i == 1,
            renderBuilder: (value) => Text(value),
          )),
      ],
    ))));
    await tester.pumpAndSettle();
    EditableTextState editor(int index) => tester.state<EditableTextState>(
      find.descendant(of: find.byKey(ValueKey<String>('ink-$index')), matching: find.byType(EditableText)),
    );
    int lines(int index) => editor(index).renderEditable
        .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length))
        .map((box) => box.top).toSet().length;

    expect(lines(0), 2, reason: 'The uncompensated native caret must reproduce the wrapping defect.');
    expect(lines(1), 1, reason: 'All printed text must fit the unchanged ink column.');
    for (var i = 0; i < 2; i++) {
      expect(tester.getSize(find.byKey(ValueKey<String>('ink-$i'))).width, width);
      expect(editor(i).renderEditable.cursorWidth, 2);
      expect(editor(i).widget.style.fontSize, 14);
    }
    expect(editor(1).renderEditable.size.width, width + 3);
    expect(editor(0).renderEditable.size.width, width);
    final before = tester.getRect(find.byKey(const ValueKey<String>('ink-1')));
    final native = editor(1);
    await tester.tap(find.byKey(const ValueKey<String>('ink-1')));
    await tester.pumpAndSettle();
    expect(identical(editor(1), native), isTrue);
    expect(native.widget.focusNode.hasFocus, isTrue);
    expect(tester.getRect(find.byKey(const ValueKey<String>('ink-1'))), before);
    expect(controllers[1].text, text);
    expect(tester.takeException(), isNull);
  });
}
