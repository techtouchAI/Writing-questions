import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

/// نوع العنصر العائم فوق لوحة ورقة الاختبار.
enum FloatingElementType {
  /// صورة نقطية (bytes بصيغة png/jpg/...).
  image,

  /// شكل هندسي أساسي (مثلث/دائرة/مربع) يُرسم متجهاً.
  shape;

  static FloatingElementType parse(String? value) {
    final normalized = value?.trim() ?? '';
    for (final type in FloatingElementType.values) {
      if (type.name == normalized) {
        return type;
      }
    }
    throw FormatException(
      'FloatingElementType: نوع عنصر غير معروف (${value ?? 'مفقود'}).',
    );
  }
}

/// الأشكال الهندسية الأساسية المدعومة (الدعم العلمي: مثلثات/دوائر/مربعات).
enum FloatingShapeType {
  triangle,
  circle,
  square;

  static FloatingShapeType parse(String? value) {
    final normalized = value?.trim() ?? '';
    for (final shape in FloatingShapeType.values) {
      if (shape.name == normalized) {
        return shape;
      }
    }
    throw FormatException(
      'FloatingShapeType: شكل هندسي غير معروف (${value ?? 'مفقود'}).',
    );
  }
}

/// عنصر حر الطيران فوق ورقة الاختبار (صورة/شكل) بإحداثيات مطلقة.
///
/// الإحداثيات (`dx`, `dy`) والمقاسات (`width`, `height`) **بكسلات منطقي
/// نسبةً إلى لوحة الورقة A4 كاملة** (انظر `ExamCanvasGeometry`)، فتنتقل
/// 1:1 إلى `pw.Positioned` داخل `pw.Stack` في محرك الـ PDF كنقاط مطلقة.
class FloatingElement {
  FloatingElement({
    String? id,
    required this.type,
    this.shape,
    Uint8List? bytes,
    this.svgSource,
    required this.dx,
    required this.dy,
    required this.width,
    required this.height,
  })  : id = id ?? const Uuid().v4(),
        bytes = bytes == null ? null : Uint8List.fromList(bytes) {
    if (type == FloatingElementType.shape && shape == null) {
      throw ArgumentError('العنصر من نوع شكل يجب أن يحدد الشكل الهندسي.');
    }
    if (type == FloatingElementType.image && (bytes == null || bytes.isEmpty)) {
      throw ArgumentError('العنصر من نوع صورة يجب أن يحتوي بايتات الصورة.');
    }
  }

  final String id;
  final FloatingElementType type;

  /// الشكل الهندسي (لأنواع [FloatingElementType.shape]).
  final FloatingShapeType? shape;

  /// بايتات الصورة النقطية (لأنواع [FloatingElementType.image]).
  final Uint8List? bytes;

  /// مصدر SVG اختياري (بديل متجه للشكل) يُرسم مباشرة في الـ PDF.
  final String? svgSource;

  double dx;
  double dy;
  double width;
  double height;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'shape': shape?.name,
      'bytes': bytes == null ? null : base64Encode(bytes!),
      'svgSource': svgSource,
      'dx': dx,
      'dy': dy,
      'width': width,
      'height': height,
    };
  }

  /// يقرأ عنصراً عائماً **بشكل صارم**؛ التركيب التالف يرمي [FormatException].
  factory FloatingElement.fromMap(Map<String, dynamic> map) {
    final rawType = map['type'];
    if (rawType is! String) {
      throw const FormatException('FloatingElement: حقل النوع (type) مفقود أو ليس نصاً.');
    }
    final type = FloatingElementType.parse(rawType);

    final rawShape = map['shape'];
    if (rawShape != null && rawShape is! String) {
      throw const FormatException('FloatingElement: حقل الشكل (shape) يجب أن يكون نصاً.');
    }
    final shape =
        rawShape == null ? null : FloatingShapeType.parse(rawShape as String);
    if (type == FloatingElementType.shape && shape == null) {
      throw const FormatException('FloatingElement: عنصر الشكل بدون تحديد الشكل الهندسي.');
    }

    Uint8List? bytes;
    final rawBytes = map['bytes'];
    if (rawBytes != null) {
      if (rawBytes is! String) {
        throw const FormatException('FloatingElement: بايتات الصورة يجب أن تكون نص base64.');
      }
      try {
        bytes = base64Decode(rawBytes);
      } on FormatException {
        throw const FormatException('FloatingElement: ترميز base64 للصورة تالف.');
      }
    }
    if (type == FloatingElementType.image && (bytes == null || bytes.isEmpty)) {
      throw const FormatException('FloatingElement: عنصر صورة بدون بايتات.');
    }

    final rawSvg = map['svgSource'];
    if (rawSvg != null && rawSvg is! String) {
      throw const FormatException('FloatingElement: مصدر SVG يجب أن يكون نصاً.');
    }

    final dx = _coordinate(map['dx'], 'dx');
    final dy = _coordinate(map['dy'], 'dy');
    final width = _coordinate(map['width'], 'width', positive: true);
    final height = _coordinate(map['height'], 'height', positive: true);

    return FloatingElement(
      id: map['id'] is String && (map['id'] as String).trim().isNotEmpty
          ? map['id'] as String
          : null,
      type: type,
      shape: shape,
      bytes: bytes,
      svgSource: rawSvg as String?,
      dx: dx,
      dy: dy,
      width: width,
      height: height,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory FloatingElement.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('FloatingElement JSON must contain an object.');
    }
    return FloatingElement.fromMap(Map<String, dynamic>.from(decoded));
  }

  FloatingElement copyWith({double? dx, double? dy, double? width, double? height}) {
    return FloatingElement(
      id: id,
      type: type,
      shape: shape,
      bytes: bytes,
      svgSource: svgSource,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  static double _coordinate(Object? value, String field, {bool positive = false}) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('FloatingElement: إحداثي $field غير صالح (${value ?? 'مفقود'}).');
    }
    if (positive && parsed <= 0) {
      throw FormatException('FloatingElement: مقاس $field يجب أن يكون موجباً ($parsed).');
    }
    return parsed;
  }
}
