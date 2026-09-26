import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/exam_document.dart';
import '../../providers/exam_document_provider.dart';
import '../../providers/exam_wizard_controller.dart';
import 'exam_preview_screen.dart';
import 'header_step_screen.dart';
import 'question_step_screen.dart';

/// خطوات المعالج المتسلسل.
enum WizardStep { header, questions, preview }

/// المعالج المتسلسل لإنشاء النموذج الوزاري (Wizard Flow):
///
/// 1. الترويسة (يمين/وسط/يسار) ← 2. إعداد الأسئلة سؤالاً سؤالاً ←
/// 3. المعاينة A4 (تحرير مباشر، سحب وإفلات، أدوات عائمة، تصدير PDF).
///
/// يملك [ExamWizardController] ويوفّره لكل الخطوات؛ زر الرجوع في النظام
/// يعود خطوة واحدة بدل الخروج مباشرة.
///
/// **الحفظ التلقائي**: فور توفر مزود المكتبة فوق الشاشة يُفعَّل الحفظ
/// الصامت بعد كل تعديل (بتهدئة ثانيتين)، وتُسجَّل الورقة كآخر ورقة
/// مفتوحة — فإغلاق التطبيق في أي لحظة لا يُضيع العمل، وعند العودة يجد
/// المدرس ورقته (ولو مسودة) في المكتبة مع لافتة «متابعة العمل».
/// عند الخروج يُفرَّغ أي حفظ معلّق فوراً.
class ExamWizardScreen extends StatefulWidget {
  const ExamWizardScreen({super.key, this.existingDocument, this.initialStep});

  final ExamDocument? existingDocument;

  /// الخطوة الابتدائية (افتراضياً: المعاينة لنموذج محفوظ، والترويسة لنموذج جديد).
  final WizardStep? initialStep;

  @override
  State<ExamWizardScreen> createState() => _ExamWizardScreenState();
}

class _ExamWizardScreenState extends State<ExamWizardScreen> {
  late final ExamWizardController _controller;
  late WizardStep _step;
  bool _autoSaveWired = false;

  @override
  void initState() {
    super.initState();
    _controller = ExamWizardController(document: widget.existingDocument);
    _step = widget.initialStep ??
        (widget.existingDocument == null ? WizardStep.header : WizardStep.preview);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wireAutoSaveOnce();
  }

  /// يفعّل الحفظ التلقائي مرة واحدة متى توفر مزود المكتبة.
  ///
  /// الشاشة قد تُفتح مستقلة (كما في اختبارات الواجهة) بلا مزود فوقها؛
  /// عندها يبقى التحرير يعمل كاملاً دون حفظ تلقائي.
  void _wireAutoSaveOnce() {
    if (_autoSaveWired) {
      return;
    }
    ExamDocumentProvider? library;
    try {
      library = context.read<ExamDocumentProvider>();
    } catch (_) {
      return;
    }
    _autoSaveWired = true;
    final provider = library;
    _controller.enableAutoSave(
      (document) => provider.saveDocument(document.touched()),
    );
    // تسجيل الورقة كآخر ورقة مفتوحة (لافتة المتابعة + استعادة الجلسة).
    provider.saveLastOpenDocumentId(_controller.document.id);
  }

  @override
  void dispose() {
    // تفريغ أي حفظ معلّق قبل التحرير حتى لا يضيع آخر تعديل عند الخروج.
    unawaited(_controller.flushAutoSave());
    _controller.dispose();
    super.dispose();
  }

  void _goTo(WizardStep step) => setState(() => _step = step);

  bool _handleBack() {
    switch (_step) {
      case WizardStep.header:
        return true;
      case WizardStep.questions:
        _goTo(WizardStep.header);
        return false;
      case WizardStep.preview:
        _goTo(WizardStep.questions);
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ExamWizardController>.value(
      value: _controller,
      child: PopScope(
        canPop: _step == WizardStep.header,
        onPopInvoked: (didPop) {
          if (!didPop) {
            _handleBack();
          }
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case WizardStep.header:
        return HeaderStepScreen(
          key: const ValueKey<WizardStep>(WizardStep.header),
          initialHeader: _controller.document.header,
          initialName: _controller.document.name,
          initialSettings: _controller.document.settings,
          onNext: (header, name, settings) {
            _controller
              ..updateHeader(header)
              ..updateName(name)
              ..updateSettings(settings)
              ..openQuestion(0);
            _goTo(WizardStep.questions);
          },
          // مسودة الترويسة عند الخروج المبكر: تُحفظ في المتحكم (ومن ثم
          // بالحفظ التلقائي) دون انتقال للخطوة التالية.
          onDraft: (header, name, settings) {
            _controller
              ..updateHeader(header)
              ..updateName(name)
              ..updateSettings(settings);
          },
        );
      case WizardStep.questions:
        return QuestionStepScreen(
          key: const ValueKey<WizardStep>(WizardStep.questions),
          onBack: () => _goTo(WizardStep.header),
          onFinish: () => _goTo(WizardStep.preview),
        );
      case WizardStep.preview:
        return ExamPreviewScreen(
          key: const ValueKey<WizardStep>(WizardStep.preview),
          onBackToQuestions: () => _goTo(WizardStep.questions),
        );
    }
  }
}
