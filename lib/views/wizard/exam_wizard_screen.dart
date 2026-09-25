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
/// 3. المعاينة A4 (تحرير مباشر، سحب وإفلات، أدوات عائمة، تصدير PDF / Word).
///
/// يملك [ExamWizardController] ويوفّره لكل الخطوات؛ زر الرجوع في النظام
/// يعود خطوة واحدة بدل الخروج مباشرة، مع تفعيل الحفظ التلقائي الفوري.
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

  @override
  void initState() {
    super.initState();
    _controller = ExamWizardController(document: widget.existingDocument);
    _step = widget.initialStep ??
        (widget.existingDocument == null ? WizardStep.header : WizardStep.preview);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ExamDocumentProvider>();
      _controller.enableAutoSave((doc) async {
        await provider.saveDocument(doc.touched());
      });
    });
  }

  @override
  void dispose() {
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
