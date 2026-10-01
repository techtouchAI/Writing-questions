import 'exam_catalog.dart';

/// كتلة توقيع واحدة في التذييل: لقب (قائمة منسدلة) واسم (مدخل حر).
class SignatureModel {
  const SignatureModel({
    this.title = SignatureTitle.lecturer,
    this.name = '',
  });

  final SignatureTitle title;

  /// اسم الموقّع (الفارغ يُطبع خطاً منقطاً للتوقيع اليدوي).
  final String name;

  SignatureModel copyWith({SignatureTitle? title, String? name}) {
    return SignatureModel(
      title: title ?? this.title,
      name: name ?? this.name,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'title': title.name, 'name': name};
  }

  /// قراءة متسامحة: أي قيمة غير خريطة تعطي كتلة افتراضية.
  factory SignatureModel.fromValue(Object? value) {
    if (value is! Map) {
      return const SignatureModel();
    }
    return SignatureModel(
      title: SignatureTitle.parse(value['title']),
      name: value['name']?.toString() ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SignatureModel && other.title == title && other.name == name;

  @override
  int get hashCode => Object.hash(title, name);
}

/// تذييل الورقة: عبارة ختامية في الوسط وكتلتا توقيع على الجانبين.
///
/// يُرسم في أسفل **آخر صفحة** فقط (أسفل الأسئلة المولَّدة مباشرةً):
/// - الوسط: [closingPhrase] المختارة من القائمة المنسدلة (فارغة = مخفية).
/// - اليسار: التوقيع الأساسي [primary] دائماً.
/// - اليمين: التوقيع الثاني [secondary] **فقط** إذا أضافه المدرس صراحةً.
///
/// الجهات فيزيائية (يسار/يمين الورقة) بغض النظر عن اتجاه منطقة الأسئلة.
class ExamFooterModel {
  const ExamFooterModel({
    this.closingPhrase = ExamCatalog.defaultClosingPhrase,
    this.primary = const SignatureModel(),
    this.secondary,
  });

  /// العبارة الختامية (فارغة = لا تُطبع).
  final String closingPhrase;

  /// التوقيع الأساسي (اليسار).
  final SignatureModel primary;

  /// التوقيع الثاني (اليمين) — `null` ما لم يُضَف صراحةً.
  final SignatureModel? secondary;

  bool get hasSecondary => secondary != null;

  ExamFooterModel copyWith({
    String? closingPhrase,
    SignatureModel? primary,
    SignatureModel? Function()? secondary,
  }) {
    return ExamFooterModel(
      closingPhrase: closingPhrase ?? this.closingPhrase,
      primary: primary ?? this.primary,
      secondary: secondary != null ? secondary() : this.secondary,
    );
  }

  /// يضيف توقيعاً ثانياً مطابقاً للأول في اللقب (الاسم فارغ ليكتبه المدرس).
  ExamFooterModel withSecondaryAdded() {
    if (hasSecondary) {
      return this;
    }
    return copyWith(secondary: () => SignatureModel(title: primary.title));
  }

  /// يزيل التوقيع الثاني فيعود التذييل لتوقيع واحد.
  ExamFooterModel withSecondaryRemoved() => copyWith(secondary: () => null);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'closingPhrase': closingPhrase,
      'primarySignature': primary.toMap(),
      if (secondary != null) 'secondarySignature': secondary!.toMap(),
    };
  }

  /// قراءة متسامحة: غياب التذييل أو تلفه يعطي التذييل الافتراضي.
  factory ExamFooterModel.fromValue(Object? value) {
    if (value is! Map) {
      return const ExamFooterModel();
    }
    final rawSecondary = value['secondarySignature'];
    return ExamFooterModel(
      closingPhrase: value['closingPhrase']?.toString() ??
          ExamCatalog.defaultClosingPhrase,
      primary: SignatureModel.fromValue(value['primarySignature']),
      secondary:
          rawSecondary is Map ? SignatureModel.fromValue(rawSecondary) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExamFooterModel &&
      other.closingPhrase == closingPhrase &&
      other.primary == primary &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(closingPhrase, primary, secondary);
}
