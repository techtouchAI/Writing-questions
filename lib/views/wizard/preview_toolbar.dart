import 'package:flutter/material.dart';

import '../../models/floating_element.dart';
import '../../models/paper_font.dart';
import '../../models/paper_text_style.dart';

/// شريط أدوات المعاينة — يظهر **فقط** في مرحلة المعاينة.
///
/// شريط شفاف مدمج بأسلوب Word المبسّط: عرض (تكبير/تصغير/ملاءمة/توسيط/قفل)
/// وتنسيق نص (خط/حجم/عريض/مائل/تحته خط/محاذاة/إطار) وإدراج (صورة/شكل/
/// مربع نص/فاصل) وتصدير (PDF/Word) — بواجهة عربية واضحة.
class PreviewToolbar extends StatelessWidget {
  const PreviewToolbar({
    super.key,
    required this.selectionLabel,
    required this.canUndo,
    required this.onUndo,
    required this.canRedo,
    required this.onRedo,
    required this.locked,
    required this.onToggleLock,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onFit,
    required this.onCenter,
    required this.multiSelect,
    required this.onToggleMultiSelect,
    required this.onToggleSelectAll,
    required this.allBlocksSelected,
    required this.selectedBlockCount,
    required this.totalBlockCount,
    required this.formatCount,
    required this.activeFont,
    required this.onFontChanged,
    required this.activeFontSize,
    required this.onFontSizeChanged,
    required this.isBold,
    required this.onToggleBold,
    required this.isItalic,
    required this.onToggleItalic,
    required this.isUnderline,
    required this.onToggleUnderline,
    required this.activeAlign,
    required this.onAlignChanged,
    required this.activeLineHeight,
    required this.onLineHeightChanged,
    required this.activeParagraphSpacing,
    required this.onParagraphSpacingChanged,
    required this.activeQuestionSpacing,
    required this.onQuestionSpacingChanged,
    required this.activeColor,
    required this.colorTooltip,
    required this.onColorChanged,
    required this.hasFrame,
    required this.onToggleFrame,
    required this.onAddImage,
    required this.onAddShape,
    required this.onAddTextBox,
    required this.onAddDivider,
    required this.showFormulas,
    required this.onToggleFormulas,
    required this.onSave,
    required this.onExportPdf,
    required this.onExportWord,
    required this.isBusy,
  });

  /// وصف العنصر المستهدف («س1»، «فرعان»...) — فارغ = بلا تحديد.
  final String selectionLabel;

  final bool canUndo;
  final VoidCallback onUndo;
  final bool canRedo;
  final VoidCallback onRedo;

  final bool locked;
  final VoidCallback onToggleLock;

  /// نسبة التكبير (1.0 = 100%).
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;
  final VoidCallback onFit;
  final VoidCallback onCenter;

  final bool multiSelect;
  final VoidCallback onToggleMultiSelect;

  /// زر «تحديد الكل» الملاصق لزر التحديد المتعدد: يحدد أسئلة الورقة
  /// وفروعها دفعة واحدة، ويتحول «إلغاء تحديد الكل» عندما تكون محددة.
  final VoidCallback onToggleSelectAll;
  final bool allBlocksSelected;

  /// عدّاد التحديد المعروض في الشريط أثناء وضع التحديد المتعدد.
  final int selectedBlockCount;
  final int totalBlockCount;

  /// تنسيق الأعداد بأرقام الورقة نفسها (`document.formatNumber`).
  final String Function(num) formatCount;

  /// تنسيق التحديد الحالي (`null` = مختلط/بلا تحديد).
  final PaperFont? activeFont;
  final ValueChanged<PaperFont?> onFontChanged;
  final double? activeFontSize;
  final ValueChanged<double?> onFontSizeChanged;
  final bool? isBold;
  final VoidCallback onToggleBold;
  final bool? isItalic;
  final VoidCallback onToggleItalic;
  final bool? isUnderline;
  final VoidCallback onToggleUnderline;
  final PaperAlign? activeAlign;
  final ValueChanged<PaperAlign> onAlignChanged;

  /// تباعد أسطر التحديد (`null` = تلقائي/الورقة، NaN = مخصص...).
  final double? activeLineHeight;
  final ValueChanged<double?> onLineHeightChanged;

  /// المسافة بين الفقرات/الأسطر المنفصلة بالبكسل المنطقي.
  final double? activeParagraphSpacing;
  final ValueChanged<double?> onParagraphSpacingChanged;

  /// المسافة بعد السؤال النشط بالبكسل (null = تحديد متعدد بقيم مختلفة).
  final double? activeQuestionSpacing;
  final ValueChanged<double> onQuestionSpacingChanged;

  /// لون النص الحالي ARGB (`null` = تلقائي، -1 = مخصص...).
  final int? activeColor;
  final String colorTooltip;
  final ValueChanged<int?> onColorChanged;
  final bool? hasFrame;
  final VoidCallback onToggleFrame;

  final VoidCallback onAddImage;
  final ValueChanged<FloatingShapeType> onAddShape;
  final VoidCallback onAddTextBox;
  final VoidCallback onAddDivider;

  final bool showFormulas;
  final VoidCallback onToggleFormulas;

  final VoidCallback onSave;
  final VoidCallback onExportPdf;
  final VoidCallback onExportWord;
  final bool isBusy;

  static const List<double> fontSizes = <double>[
    8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28,
  ];

  /// إعدادات تباعد الأسطر المسبقة (1.0 مفرد ... 3.0) + مخصص.
  static const List<double> lineSpacings = <double>[
    1.0, 1.15, 1.5, 2.0, 2.5, 3.0,
  ];

  /// مسافة بعد كل فقرة، مستقلة عن ارتفاع السطر داخلها.
  static const List<double> paragraphSpacings = <double>[0, 1, 2, 4, 8, 12, 16, 24];

  /// مسافات جاهزة بين الأسئلة؛ الصفر يلغي الفراغ الإضافي تماماً.
  static const List<double> questionSpacings = <double>[0, 2, 4, 6, 10, 16, 24, 40];

  /// قيمة «مخصص...» في قائمة اللون — تفتح شاشة المعاينة حوار HEX.
  static const int customColorSentinel = -1;

  /// ألوان النص الجاهزة (ARGB) — تبقى حياً في اللوحة والمطبوع.
  static const List<(int, String)> textColors = <(int, String)>[
    (0xFF000000, 'أسود'),
    (0xFF1E3A8A, 'كحلي'),
    (0xFFB91C1C, 'خمري'),
    (0xFF15803D, 'أخضر'),
    (0xFF7E22CE, 'بنفسجي'),
    (0xFFC2410C, 'برتقالي'),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface.withOpacity(0.94),
      elevation: 2,
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          children: <Widget>[
            _ToolButton(
              icon: Icons.undo,
              tooltip: 'تراجع',
              onTap: canUndo && !isBusy ? onUndo : null,
            ),
            _ToolButton(
              icon: Icons.redo,
              tooltip: 'إعادة',
              onTap: canRedo && !isBusy ? onRedo : null,
            ),
            _ToolButton(
              icon: locked ? Icons.lock : Icons.lock_open,
              tooltip: locked ? 'فتح القفل (السماح بالتحريك)' : 'قفل التحريك',
              onTap: onToggleLock,
              selected: locked,
            ),
            const _Divider(),
            _ToolButton(icon: Icons.remove, tooltip: 'تصغير', onTap: onZoomOut),
            _ZoomLabel(zoom: zoom, onTap: onZoomReset),
            _ToolButton(icon: Icons.add, tooltip: 'تكبير', onTap: onZoomIn),
            _ToolButton(icon: Icons.fit_screen, tooltip: 'ملاءمة الورقة للشاشة', onTap: onFit),
            _ToolButton(
              icon: Icons.center_focus_strong,
              tooltip: 'توسيط الورقة',
              onTap: onCenter,
            ),
            _ToolButton(
              icon: Icons.select_all,
              tooltip: 'تحديد متعدد',
              onTap: onToggleMultiSelect,
              selected: multiSelect,
            ),
            _ToolButton(
              key: const ValueKey<String>('select-all-blocks'),
              icon: allBlocksSelected ? Icons.deselect : Icons.select_all,
              tooltip: allBlocksSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل',
              onTap: isBusy ? null : onToggleSelectAll,
              selected: allBlocksSelected,
            ),
            if (multiSelect)
              _SelectionCounter(
                selected: selectedBlockCount,
                total: totalBlockCount,
                formatCount: formatCount,
              ),
            const _Divider(),
            _FontMenu(
              activeFont: activeFont,
              onChanged: isBusy ? null : onFontChanged,
            ),
            _FontSizeMenu(
              activeFontSize: activeFontSize,
              onChanged: isBusy ? null : onFontSizeChanged,
            ),
            _ToolButton(
              icon: Icons.format_bold,
              tooltip: 'عريض',
              onTap: isBusy ? null : onToggleBold,
              selected: isBold == true,
            ),
            _ToolButton(
              icon: Icons.format_italic,
              tooltip: 'مائل',
              onTap: isBusy ? null : onToggleItalic,
              selected: isItalic == true,
            ),
            _ToolButton(
              icon: Icons.format_underline,
              tooltip: 'تحته خط',
              onTap: isBusy ? null : onToggleUnderline,
              selected: isUnderline == true,
            ),
            _ToolButton(
              icon: Icons.format_align_right,
              tooltip: 'محاذاة لليمين',
              onTap: isBusy ? null : () => onAlignChanged(PaperAlign.right),
              selected: activeAlign == PaperAlign.right,
            ),
            _ToolButton(
              icon: Icons.format_align_center,
              tooltip: 'توسيط',
              onTap: isBusy ? null : () => onAlignChanged(PaperAlign.center),
              selected: activeAlign == PaperAlign.center,
            ),
            _ToolButton(
              icon: Icons.format_align_left,
              tooltip: 'محاذاة لليسار',
              onTap: isBusy ? null : () => onAlignChanged(PaperAlign.left),
              selected: activeAlign == PaperAlign.left,
            ),
            _ToolButton(
              icon: Icons.format_align_justify,
              tooltip: 'ضبط',
              onTap: isBusy ? null : () => onAlignChanged(PaperAlign.justify),
              selected: activeAlign == PaperAlign.justify,
            ),
            _LineSpacingMenu(
              activeLineHeight: activeLineHeight,
              onChanged: isBusy ? null : onLineHeightChanged,
            ),
            _ParagraphSpacingMenu(
              activeSpacing: activeParagraphSpacing,
              onChanged: isBusy ? null : onParagraphSpacingChanged,
            ),
            _QuestionSpacingMenu(
              activeSpacing: activeQuestionSpacing,
              onChanged: isBusy ? null : onQuestionSpacingChanged,
            ),
            _ColorMenu(
              activeColor: activeColor,
              tooltip: colorTooltip,
              onChanged: isBusy ? null : onColorChanged,
            ),
            _ToolButton(
              icon: Icons.border_outer,
              tooltip: 'إطار حول التحديد',
              onTap: isBusy ? null : onToggleFrame,
              selected: hasFrame == true,
            ),
            const _Divider(),
            _ToolButton(icon: Icons.image, tooltip: 'إدراج صورة', onTap: isBusy ? null : onAddImage),
            _ShapeMenu(onAddShape: onAddShape, enabled: !isBusy),
            _ToolButton(
              icon: Icons.text_fields,
              tooltip: 'مربع نص',
              onTap: isBusy ? null : onAddTextBox,
            ),
            _ToolButton(
              icon: Icons.horizontal_rule,
              tooltip: 'إضافة فاصل',
              onTap: isBusy ? null : onAddDivider,
            ),
            _ToolButton(
              icon: Icons.functions,
              tooltip: 'شريط الصيغ والوسائط',
              onTap: onToggleFormulas,
              selected: showFormulas,
            ),
            const _Divider(),
            _ToolButton(icon: Icons.save_outlined, tooltip: 'حفظ', onTap: isBusy ? null : onSave),
            _ExportButton(label: 'PDF', tooltip: 'مراجعة وتصدير PDF', onTap: isBusy ? null : onExportPdf),
            _ExportButton(
              label: 'Word',
              tooltip: 'مراجعة وتصدير Word',
              onTap: isBusy ? null : onExportWord,
            ),
            if (selectionLabel.isNotEmpty) _SelectionChip(label: selectionLabel),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 38,
          alignment: Alignment.center,
          decoration: selected
              ? BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: Icon(
            icon,
            size: 20,
            color: onTap == null
                ? colorScheme.onSurface.withOpacity(0.35)
                : selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ZoomLabel extends StatelessWidget {
  const _ZoomLabel({required this.zoom, required this.onTap});

  final double zoom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'نسبة التكبير — انقر للعودة إلى 100%',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 52),
          alignment: Alignment.center,
          child: Text(
            '${(zoom * 100).round()}%',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

// PopupMenuButton reserves null for dismissal. Wrap nullable settings so
// choosing "automatic" still invokes onSelected.
class _MenuChoice<T> {
  const _MenuChoice(this.value);
  final T? value;
}

class _FontMenu extends StatelessWidget {
  const _FontMenu({required this.activeFont, required this.onChanged});

  final PaperFont? activeFont;
  final ValueChanged<PaperFont?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'نوع الخط',
      child: PopupMenuButton<_MenuChoice<PaperFont>>(
        enabled: onChanged != null,
        tooltip: 'نوع الخط',
        icon: const Icon(Icons.font_download_outlined, size: 20),
        onSelected: (value) => onChanged?.call(value.value),
        itemBuilder: (_) => <PopupMenuEntry<_MenuChoice<PaperFont>>>[
          PopupMenuItem<_MenuChoice<PaperFont>>(
            value: const _MenuChoice<PaperFont>(null),
            child: Text(
              activeFont == null ? '✓ افتراضي الورقة' : 'افتراضي الورقة',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const PopupMenuDivider(),
          for (final font in PaperFont.values)
            PopupMenuItem<_MenuChoice<PaperFont>>(
              value: _MenuChoice<PaperFont>(font),
              child: Text(
                '${activeFont == font ? '✓ ' : ''}${font.arabicLabel}',
                style: TextStyle(fontSize: 14, fontFamily: font.family),
              ),
            ),
        ],
      ),
    );
  }
}

class _FontSizeMenu extends StatelessWidget {
  const _FontSizeMenu({required this.activeFontSize, required this.onChanged});

  final double? activeFontSize;
  final ValueChanged<double?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final label = activeFontSize == null
        ? 'الحجم'
        : (activeFontSize! == activeFontSize!.truncateToDouble()
            ? activeFontSize!.toInt().toString()
            : activeFontSize.toString());
    return Tooltip(
      message: 'حجم الخط',
      child: PopupMenuButton<_MenuChoice<double>>(
        enabled: onChanged != null,
        tooltip: 'حجم الخط',
        onSelected: (value) => onChanged?.call(value.value),
        itemBuilder: (_) => <PopupMenuEntry<_MenuChoice<double>>>[
          const PopupMenuItem<_MenuChoice<double>>(
            value: _MenuChoice<double>(null),
            child: Text('تلقائي', style: TextStyle(fontSize: 13)),
          ),
          const PopupMenuDivider(),
          for (final size in PreviewToolbar.fontSizes)
            PopupMenuItem<_MenuChoice<double>>(
              value: _MenuChoice<double>(size),
              child: Text(
                '${activeFontSize == size ? '✓ ' : ''}${size.toInt()}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          // القيمة المميزة NaN: حقل حر لحجم مخصص (تعالجه شاشة المعاينة).
          const PopupMenuItem<_MenuChoice<double>>(
            value: _MenuChoice<double>(double.nan),
            child: Text('مخصص...', style: TextStyle(fontSize: 13)),
          ),
        ],
        child: Container(
          constraints: const BoxConstraints(minWidth: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class _LineSpacingMenu extends StatelessWidget {
  const _LineSpacingMenu({required this.activeLineHeight, required this.onChanged});

  final double? activeLineHeight;
  final ValueChanged<double?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final value = activeLineHeight;
    final label = value == null
        ? 'تباعد'
        : (value == value.truncateToDouble()
            ? value.toInt().toString()
            : value.toString());
    // ملاحظة: PopupMenuButton يبني Tooltip داخليًا من خاصية tooltip —
    // لا نغلّفه بـ Tooltip مكرر (نظافة الوصول ودقة الاختبارات).
    return PopupMenuButton<_MenuChoice<double>>(
      enabled: onChanged != null,
      tooltip: 'تباعد الأسطر',
      onSelected: (selected) => onChanged?.call(selected.value),
      itemBuilder: (_) => <PopupMenuEntry<_MenuChoice<double>>>[
        const PopupMenuItem<_MenuChoice<double>>(
          value: _MenuChoice<double>(null),
          child: Text('تلقائي', style: TextStyle(fontSize: 13)),
        ),
        const PopupMenuDivider(),
        for (final spacing in PreviewToolbar.lineSpacings)
          PopupMenuItem<_MenuChoice<double>>(
            value: _MenuChoice<double>(spacing),
            child: Text(
              '${activeLineHeight == spacing ? '✓ ' : ''}$spacing',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        // القيمة المميزة NaN: حقل حر لتباعد مخصص (تعالجه شاشة المعاينة).
        const PopupMenuItem<_MenuChoice<double>>(
          value: _MenuChoice<double>(double.nan),
          child: Text('مخصص...', style: TextStyle(fontSize: 13)),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _ParagraphSpacingMenu extends StatelessWidget {
  const _ParagraphSpacingMenu({
    required this.activeSpacing,
    required this.onChanged,
  });

  final double? activeSpacing;
  final ValueChanged<double?>? onChanged;

  static String _label(double value) => value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();

  @override
  Widget build(BuildContext context) {
    final value = activeSpacing;
    return PopupMenuButton<_MenuChoice<double>>(
      enabled: onChanged != null,
      tooltip: 'المسافة بين الفقرات',
      onSelected: (selected) => onChanged?.call(selected.value),
      itemBuilder: (_) => <PopupMenuEntry<_MenuChoice<double>>>[
        PopupMenuItem<_MenuChoice<double>>(
          value: const _MenuChoice<double>(null),
          child: Text(
            value == null ? '✓ تلقائي' : 'تلقائي',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const PopupMenuDivider(),
        for (final spacing in PreviewToolbar.paragraphSpacings)
          PopupMenuItem<_MenuChoice<double>>(
            value: _MenuChoice<double>(spacing),
            child: Text(
              '${value == spacing ? '✓ ' : ''}${_label(spacing)} بكسل'
              '${spacing == 0 ? ' — بلا فراغ' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<_MenuChoice<double>>(
          value: _MenuChoice<double>(double.nan),
          child: Text('مخصص...', style: TextStyle(fontSize: 13)),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minWidth: 52),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.format_line_spacing, size: 20),
            const SizedBox(width: 2),
            Text(
              value == null ? 'فقرات' : '${_label(value)}px',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionSpacingMenu extends StatelessWidget {
  const _QuestionSpacingMenu({required this.activeSpacing, required this.onChanged});

  final double? activeSpacing;
  final ValueChanged<double>? onChanged;

  static String _label(double value) => value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();

  @override
  Widget build(BuildContext context) {
    final value = activeSpacing;
    return PopupMenuButton<double>(
      enabled: onChanged != null,
      tooltip: 'المسافة بين الأسئلة',
      onSelected: (spacing) => onChanged?.call(spacing),
      itemBuilder: (_) => <PopupMenuEntry<double>>[
        for (final spacing in PreviewToolbar.questionSpacings)
          PopupMenuItem<double>(
            value: spacing,
            child: Text(
              '${value == spacing ? '✓ ' : ''}${_label(spacing)} بكسل'
              '${spacing == 0 ? ' — بلا فراغ' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<double>(
          value: double.nan,
          child: Text('قيمة مخصصة...', style: TextStyle(fontSize: 13)),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(minWidth: 50),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.height, size: 20),
            const SizedBox(width: 2),
            Text(
              value == null ? 'فراغ' : '${_label(value)}px',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorMenu extends StatelessWidget {
  const _ColorMenu({
    required this.activeColor,
    required this.tooltip,
    required this.onChanged,
  });

  final int? activeColor;
  final String tooltip;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final current = activeColor;
    // ملاحظة: PopupMenuButton يبني Tooltip داخليًا من خاصية tooltip —
    // لا نغلّفه بـ Tooltip مكرر (نظافة الوصول ودقة الاختبارات).
    return PopupMenuButton<_MenuChoice<int>>(
      enabled: onChanged != null,
      tooltip: tooltip,
      icon: Icon(
        Icons.format_color_text,
        size: 20,
        color: current == null ? null : Color(current),
      ),
      onSelected: (selected) => onChanged?.call(selected.value),
      itemBuilder: (_) => <PopupMenuEntry<_MenuChoice<int>>>[
        PopupMenuItem<_MenuChoice<int>>(
          value: const _MenuChoice<int>(null),
          child: Text(
            current == null ? '✓ تلقائي' : 'تلقائي',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const PopupMenuDivider(),
        for (final swatch in PreviewToolbar.textColors)
          PopupMenuItem<_MenuChoice<int>>(
            value: _MenuChoice<int>(swatch.$1),
            child: Row(
              children: <Widget>[
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Color(swatch.$1),
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${current == swatch.$1 ? '✓ ' : ''}${swatch.$2}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        // القيمة المميزة -1: حوار HEX مخصص (تعالجه شاشة المعاينة).
        const PopupMenuItem<_MenuChoice<int>>(
          value: _MenuChoice<int>(PreviewToolbar.customColorSentinel),
          child: Text('مخصص...', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}

class _ShapeMenu extends StatelessWidget {
  const _ShapeMenu({required this.onAddShape, required this.enabled});

  final ValueChanged<FloatingShapeType> onAddShape;
  final bool enabled;

  static const List<(FloatingShapeType, IconData, String)> _shapes =
      <(FloatingShapeType, IconData, String)>[
    (FloatingShapeType.rectangle, Icons.rectangle_outlined, 'مستطيل'),
    (FloatingShapeType.square, Icons.crop_square, 'مربع'),
    (FloatingShapeType.circle, Icons.circle_outlined, 'دائرة'),
    (FloatingShapeType.triangle, Icons.change_history, 'مثلث'),
    (FloatingShapeType.line, Icons.remove, 'خط'),
    (FloatingShapeType.arrow, Icons.arrow_forward, 'سهم'),
  ];

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'إدراج شكل',
      child: PopupMenuButton<FloatingShapeType>(
        enabled: enabled,
        tooltip: 'إدراج شكل',
        icon: const Icon(Icons.interests_outlined, size: 20),
        onSelected: onAddShape,
        itemBuilder: (_) => <PopupMenuEntry<FloatingShapeType>>[
          for (final shape in _shapes)
            PopupMenuItem<FloatingShapeType>(
              value: shape.$1,
              child: Row(
                children: <Widget>[
                  Icon(shape.$2, size: 18),
                  const SizedBox(width: 8),
                  Text(shape.$3, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.label, required this.tooltip, required this.onTap});

  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null
                ? colorScheme.surfaceContainerHighest
                : colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: onTap == null
                  ? colorScheme.onSurface.withOpacity(0.4)
                  : colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// عدّاد «المحدد ٣ من ١٢» — يُبنى من عدّاد الكتل القابل للتحديد (أسئلة
/// وفروع) فيظهر فوراً أثر «تحديد الكل» وأثر أي نقرة إضافة/إزالة.
class _SelectionCounter extends StatelessWidget {
  const _SelectionCounter({
    required this.selected,
    required this.total,
    required this.formatCount,
  });

  final int selected;
  final int total;
  final String Function(num) formatCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey<String>('preview-selection-count'),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'المحدد ${formatCount(selected)} من ${formatCount(total)}',
        style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}

class _SelectionChip extends StatelessWidget {
  const _SelectionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}
