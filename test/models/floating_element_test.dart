import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:writing_questions_app/models/floating_element.dart';

void main() {
  group('FloatingElement', () {
    test('round-trips an image element with exact canvas coordinates', () {
      final element = FloatingElement(
        id: 'img-1',
        type: FloatingElementType.image,
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        dx: 120.5,
        dy: 340.25,
        width: 180,
        height: 120,
      );

      final restored = FloatingElement.fromJson(element.toJson());

      expect(restored.id, 'img-1');
      expect(restored.type, FloatingElementType.image);
      expect(restored.bytes, <int>[1, 2, 3, 4]);
      expect(restored.dx, 120.5);
      expect(restored.dy, 340.25);
      expect(restored.width, 180);
      expect(restored.height, 120);
    });

    test('round-trips a shape element (triangle/circle/square)', () {
      for (final shape in FloatingShapeType.values) {
        final element = FloatingElement(
          type: FloatingElementType.shape,
          shape: shape,
          svgSource: '<svg/>',
          dx: 10,
          dy: 20,
          width: 50,
          height: 50,
        );

        final restored = FloatingElement.fromMap(element.toMap());
        expect(restored.shape, shape);
        expect(restored.svgSource, '<svg/>');
      }
    });

    test('move/resize via copyWith keeps identity', () {
      final element = FloatingElement(
        id: 'shape-1',
        type: FloatingElementType.shape,
        shape: FloatingShapeType.circle,
        dx: 0,
        dy: 0,
        width: 40,
        height: 40,
      );

      final moved = element.copyWith(dx: 90, dy: 180, width: 60, height: 60);
      expect(moved.id, 'shape-1');
      expect(moved.shape, FloatingShapeType.circle);
      expect(moved.dx, 90);
      expect(moved.dy, 180);
    });

    test('throws FormatException for unknown type or invalid structure', () {
      expect(
        () => FloatingElement.fromMap(const <String, dynamic>{
          'type': 'نوع_غير_معروف',
          'dx': 0,
          'dy': 0,
          'width': 10,
          'height': 10,
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => FloatingElement.fromMap(const <String, dynamic>{
          'type': 'shape',
          'shape': 'hexagon',
          'dx': 0,
          'dy': 0,
          'width': 10,
          'height': 10,
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => FloatingElement.fromMap(const <String, dynamic>{
          'type': 'image',
          'bytes': 'not-base64-!!!',
          'dx': 0,
          'dy': 0,
          'width': 10,
          'height': 10,
        }),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => FloatingElement.fromMap(const <String, dynamic>{
          'type': 'shape',
          'shape': 'circle',
          'dx': 'غير رقم',
          'dy': 0,
          'width': 10,
          'height': 10,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects construction without the required payload', () {
      expect(
        () => FloatingElement(
          type: FloatingElementType.shape,
          dx: 0,
          dy: 0,
          width: 10,
          height: 10,
        ),
        throwsArgumentError,
      );

      expect(
        () => FloatingElement(
          type: FloatingElementType.image,
          dx: 0,
          dy: 0,
          width: 10,
          height: 10,
        ),
        throwsArgumentError,
      );
    });
  });
}
