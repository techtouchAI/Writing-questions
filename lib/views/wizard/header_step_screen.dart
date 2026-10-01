import 'package:flutter/material.dart';

import '../../layout/blueprint/exam_blueprint.dart';
import '../../models/exam_document.dart';
import '../../models/exam_footer_model.dart';
import '../../models/exam_header_model.dart';
import '../../models/paper_font.dart';
import '../../models/paper_settings.dart';
import 'header_footer_forms.dart';
import 'paper_header_footer_view.dart';

/// الخطوة 1 من المعالج: بيانات الترويسة والتذييل.
///
/// - **الترويسة** ([HeaderForm]): اسم المدرسة، البسملة، نوع الامتحان، العام
///   الدراسي والدور (وسط)، والمادة والصف والوقت (يسار).
/// - **التذييل** ([FooterForm]): العبارة الختامية وتوقيع المدرس (والثاني
///   اختيارياً).
/// - **التصميم**: خط الترويسة وحجمها وعريضها وإطار الجدول.
/// - **معاينة حية** بنفس عرض الورقة ([PaperHeaderView]/[PaperFooterView]):
///   ما يُرى هنا هو ما يُطبع.
///
/// النموذجان «حيّان»: كل تعديل يُحدّث المسودة، وتُسلَّم عند [التالي] (أو
/// عند الخروج المبكر عبر [onDraft] حتى لا يضيع ما كُتب).
class HeaderStepScreen extends StatefulWidget {
  const HeaderStepScreen({
    super.key,
    required this.initialHeader,
    required this.initialFooter,
    required this.initialName,
    required this.initialSettings,
    required this.onNext,
    this.onDraft,
  });

  final ExamHeaderModel initialHeader;
  final ExamFooterModel initialFooter;
  final String initialName;
  final PaperSettings initialSettings;

  /// يُستدعى بالترويسة والتذييل واسم الورقة والإعدادات عند [التالي].
  final void Function(
    ExamHeaderModel header,
    ExamFooterModel footer,
    String name,
    PaperSettings settings,
  ) onNext;

  /// يُستدعى بالمسودة الحالية عند التخلص من الشاشة دون [التالي] (خروج
  /// مبكر بزر الرجوع) حتى لا يضيع ما كتبه المدرس قبل الحفظ التلقائي.
  final void Function(
    ExamHeaderModel header,
    ExamFooterModel footer,
    String name,
    PaperSettings settings,
  )? onDraft;

  @override
  State<HeaderStepScreen> createState() => _HeaderStepScreenState();
}

class _HeaderStepScreenState extends State<HeaderStepScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late ExamHeaderModel _header;
  late ExamFooterModel _footer;
  late bool _headerBorder;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _header = widget.initialHeader;
    _footer = widget.initialFooter;
    _headerBorder = widget.initialSettings.headerBorder;
  }

  @override
  void dispose() {
    // خروج مبكر: حفظ المسودة (بشرط وجود اسم صالح) قبل التحرير.
    final draft = widget.onDraft;
    if (draft != null && !_submitted) {
      final name = _nameController.text.trim();
      if (name.isNotEmpty) {
        draft(_header, _footer, name, _collectSettings());
      }
    }
    _nameController.dispose();
    super.dispose();
  }

  PaperSettings _collectSettings() {
    return widget.initialSettings.copyWith(headerBorder: _headerBorder);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    _submitted = true;
    widget.onNext(_header, _footer, _nameController.text.trim(), _collectSettings());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخطوة 1: ترويسة الورقة وتذييلها')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الورقة (للتنظيم داخل التطبيق) *',
                  hintText: 'مثال: امتحان نصف السنة - الثالث المتوسط',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'اسم الورقة مطلوب.' : null,
              ),
              const SizedBox(height: 20),
              HeaderForm(
                initial: _header,
                onChanged: (header) => setState(() => _header = header),
              ),
              const SizedBox(height: 20),
              FooterForm(
                initial: _footer,
                onChanged: (footer) => setState(() => _footer = footer),
              ),
              const SizedBox(height: 20),
              _buildDesignCard(),
              const SizedBox(height: 12),
              _buildLivePreview(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      // زر المتابعة ثابت أسفل الشاشة (كخطوة الأسئلة): يبقى ظاهراً وقابلاً
      // للنقر مهما طال النموذج، بدل دفنه تحت الحقول.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.arrow_back),
            label: const Text('التالي: إعداد السؤال الأول', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }

  static const List<double> _sizes = <double>[8, 9, 10, 11, 12, 14, 16];

  /// أقرب حجم متاح في القائمة لحجم الترويسة المخزَّن (قد يكون من الشريط).
  static double _nearestSize(double? stored) {
    final target = stored ?? 10;
    return _sizes.reduce(
      (best, next) => (best - target).abs() <= (next - target).abs() ? best : next,
    );
  }

  /// بطاقة تصميم الترويسة (خط/حجم/عريض/إطار الجدول).
  Widget _buildDesignCard() {
    final style = _header.style;
    final font = style.font ?? widget.initialSettings.defaultFont;
    final size = _nearestSize(style.fontSize);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.palette_outlined, size: 18),
                SizedBox(width: 6),
                Text('تصميم الترويسة والتذييل', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<PaperFont>(
                    value: font,
                    decoration: const InputDecoration(
                      labelText: 'الخط',
                      hintText: 'اختر خط الترويسة والتذييل',
                      helperText: 'يظهر بخطه الحقيقي في القائمة والمعاينة.',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: PaperFont.values
                        .map((entry) => DropdownMenuItem<PaperFont>(
                              value: entry,
                              child: Text(
                                entry.arabicLabel,
                                style: TextStyle(fontSize: 12, fontFamily: entry.family),
                              ),
                            ))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _header = _header.copyWith(
                              style: style.copyWith(font: () => value),
                            ));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<double>(
                    value: size,
                    decoration: const InputDecoration(
                      labelText: 'الحجم',
                      hintText: 'اختر حجم خط الترويسة',
                      helperText: 'الحجم بالنقاط (8–16).',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _sizes
                        .map((entry) => DropdownMenuItem<double>(
                              value: entry,
                              child: Text('${entry.toInt()}',
                                  style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _header = _header.copyWith(
                              style: style.copyWith(fontSize: () => value),
                            ));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('خط عريض'),
              value: style.bold ?? false,
              onChanged: (value) => setState(() => _header = _header.copyWith(
                    style: style.copyWith(bold: () => value),
                  )),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('إطار حول الترويسة'),
              value: _headerBorder,
              onChanged: (value) => setState(() => _headerBorder = value),
            ),
          ],
        ),
      ),
    );
  }

  /// معاينة حية لشكل الترويسة والتذييل بعرض الورقة نفسه قبل المتابعة.
  Widget _buildLivePreview() {
    final settings = _collectSettings();
    final blueprint = ExamBlueprint.from(
      ExamDocument(
        name: _nameController.text,
        header: _header,
        footer: _footer,
        settings: settings,
      ),
    );
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.preview_outlined, size: 18),
                SizedBox(width: 6),
                Text('معاينة الترويسة والتذييل', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: <Widget>[
                  PaperHeaderView(
                    header: blueprint.header,
                    style: _header.style,
                    defaultFont: settings.defaultFont,
                    fontScale: 1,
                    heightScale: 1,
                  ),
                  const SizedBox(height: 24),
                  PaperFooterView(
                    footer: blueprint.footer,
                    style: _header.style,
                    defaultFont: settings.defaultFont,
                    fontScale: 1,
                    heightScale: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
