import '../../models/paper_font.dart';
import '../../models/paper_text_style.dart';
import '../../models/point_kind.dart';
import '../document_direction.dart';
import '../document_ir.dart';
import '../semantic/inline_nodes.dart';
import '../visual/visual_content.dart';
import '../visual/visual_metrics.dart';
import '../visual/visual_style.dart';
import '../visual/visual_typography.dart';
import 'font_metrics.dart';
import 'layout_configuration.dart';
import 'layout_document.dart';
import 'layout_units.dart';

/// Canonical, renderer-independent geometry engine.
///
/// DocumentIR is the sole semantic input. Page/style policy, math snapshot
/// dimensions, and source-authored float geometry arrive through separate
/// arguments; no resolved geometry is written back into the semantic tree.
class LayoutEngine {
  const LayoutEngine();

  LayoutDocument layout({
    required DocumentIR document,
    required LayoutConfiguration configuration,
    required FontMetricsProvider fontMetrics,
    Map<String, LayoutMathBox> mathMetrics = const <String, LayoutMathBox>{},
  }) =>
      _LayoutBuilder(
        document: document,
        configuration: configuration,
        fontMetrics: fontMetrics,
        mathMetrics: mathMetrics,
      ).build();
}

class _LayoutBuilder {
  _LayoutBuilder({
    required this.document,
    required this.configuration,
    required this.fontMetrics,
    required this.mathMetrics,
  });

  final DocumentIR document;
  final LayoutConfiguration configuration;
  final FontMetricsProvider fontMetrics;
  final Map<String, LayoutMathBox> mathMetrics;
  var _paragraphSerial = 0;
  var _logicalRunSerial = 0;

  double get _left => configuration.marginPt;
  double get _width => configuration.contentWidthPt;
  double get _pageHeight => configuration.pageSize.height;
  double get _pageWidth => configuration.pageSize.width;
  DocumentDirection get _direction => _resolveDirection(document.direction);
  double get _headerGap => _header.height > 0 ? LayoutUnits.pxToPt(10) : 0;
  double get _footerGap => _footer.height > 0 ? LayoutUnits.pxToPt(10) : 0;

  late final _FlowBlock _header = _layoutHeader(document.header);
  late final _FlowBlock _footer = _layoutFooter(document.footer);

  LayoutDocument build() {
    final questionFlows = <_QuestionFlow>[
      for (final question in document.questions)
        if (question.isPrintable) _layoutQuestion(question),
    ];
    final pagination = _paginate(questionFlows);
    final placedPages = <({
      _PageState state,
      List<LayoutBlock> blocks,
      LayoutRect? headerBounds,
      LayoutRect? footerBounds,
      LayoutRect bodyBounds,
    })>[];
    LayoutBlock? placedHeader;
    LayoutBlock? placedFooter;
    final pageOfSemanticNode = <String, ({int page, double top})>{};

    for (final pageState in pagination.pages) {
      final first = pageState.index == 0;
      final last = pageState.index == pagination.pages.length - 1;
      final headerReserve = first ? _header.height + _headerGap : 0.0;
      final footerReserve = last ? _footer.height + _footerGap : 0.0;
      final bodyTop = _top + headerReserve;
      final bodyHeight = (_contentHeight - headerReserve - footerReserve)
          .clamp(0.0, _contentHeight)
          .toDouble();
      final bodyBounds = LayoutRect.fromLTWH(_left, bodyTop, _width, bodyHeight);
      final blocks = <LayoutBlock>[];
      LayoutRect? headerBounds;
      LayoutRect? footerBounds;

      if (first) {
        placedHeader = _moveBlock(_header.block, 0, _top, id: 'header');
        headerBounds = placedHeader.rect;
        blocks.add(placedHeader);
      }
      for (final item in pageState.questions) {
        final placed = _moveBlock(
          item.flow.block,
          0,
          bodyTop + item.topInBody,
          id: item.flow.block.id,
          breakReason: item.breakReason,
        );
        blocks.add(placed);
        pageOfSemanticNode.putIfAbsent(
          placed.semanticNodeId,
          () => (page: pageState.index, top: placed.rect.top),
        );
        for (final child in placed.descendants) {
          pageOfSemanticNode.putIfAbsent(
            child.semanticNodeId,
            () => (page: pageState.index, top: child.rect.top),
          );
        }
      }
      if (last) {
        final footerTop = _pageHeight - _top - _footer.height;
        placedFooter = _moveBlock(_footer.block, 0, footerTop, id: 'footer');
        footerBounds = placedFooter.rect;
        blocks.add(placedFooter);
      }
      placedPages.add((
        state: pageState,
        blocks: blocks,
        headerBounds: headerBounds,
        footerBounds: footerBounds,
        bodyBounds: bodyBounds,
      ));
    }

    final floatPlacements = _placeFloatingElements(
      pageOfSemanticNode,
      pagination.pages.length,
    );
    final pages = <LayoutPage>[];
    for (final placed in placedPages) {
      final index = placed.state.index;
      final decorations = <LayoutDecoration>[
        if (configuration.paperSettings.pageBorder)
          LayoutDecoration(
            id: 'page/$index/border',
            semanticNodeId: 'page/$index',
            kind: LayoutDecorationKind.border,
            rect: LayoutRect.fromLTWH(_left, _top, _width, _contentHeight),
            strokeWidthPt: 1,
          ),
      ];
      pages.add(
        LayoutPage(
          index: index,
          pageSize: configuration.pageSize,
          contentBounds: LayoutRect.fromLTWH(_left, _top, _width, _contentHeight),
          bodyBounds: placed.bodyBounds,
          headerBounds: placed.headerBounds,
          footerBounds: placed.footerBounds,
          blocks: List<LayoutBlock>.unmodifiable(placed.blocks),
          floatingElements: List<LayoutFloatPlacement>.unmodifiable(
            floatPlacements.where((float) => float.pageIndex == index),
          ),
          decorations: List<LayoutDecoration>.unmodifiable(decorations),
          breakReason: placed.state.breakReason,
          usedBodyHeight: placed.state.usedHeight,
          scaleFactor: placed.state.scaleFactor,
        ),
      );
    }

    return LayoutDocument(
      source: document,
      pageSize: configuration.pageSize,
      direction: _direction,
      pages: pages,
      headerBlock: placedHeader,
      footerBlock: placedFooter,
      measurementBackend: fontMetrics.backendId,
      pageFrameImagePath: configuration.paperSettings.hasFrameImage
          ? configuration.paperSettings.frameImagePath
          : null,
    );
  }

  double get _top => configuration.marginPt;
  double get _contentHeight => configuration.contentHeightPt;

  _FlowBlock _layoutHeader(HeaderBlock header) {
    final padX = LayoutUnits.pxToPt(8);
    final padY = LayoutUnits.pxToPt(6);
    final gutter = LayoutUnits.pxToPt(8);
    final innerWidth = (_width - 2 * padX - 2 * gutter).clamp(0.0, _width).toDouble();
    final rightWidth = innerWidth * 0.3;
    final centerWidth = innerWidth * 0.4;
    final leftWidth = innerWidth * 0.3;
    final leftX = _left + padX;
    final centerX = leftX + leftWidth + gutter;
    final rightX = centerX + centerWidth + gutter;
    final headerOverride = configuration.headerStyle;
    final lineGap = headerOverride?.paragraphSpacing == null
        ? 0.0
        : LayoutUnits.pxToPt(headerOverride!.paragraphSpacing!);

    _FlowBuilder buildColumn(
      String id,
      List<HeaderLineBlock> source,
      double x,
      double width,
    ) {
      final flow = _FlowBuilder(x: x, width: width);
      for (var index = 0; index < source.length; index++) {
        final line = source[index];
        if (line.content.isEmpty) continue;
        flow.add(
          _contentBlock(
            id: '$id/line/$index',
            kind: LayoutBlockKind.body,
            semanticNode: line,
            content: line.content,
            style: _resolveStyle(
              VisualRole.headerBody,
              override: headerOverride,
              bold: line.bold,
            ),
            alignment: line.alignment,
            direction: line.direction,
            x: x,
            width: width,
          ),
          after: lineGap,
        );
      }
      return flow;
    }

    final right = buildColumn('header/right', header.rightColumn, rightX, rightWidth);
    final left = buildColumn('header/left', header.leftColumn, leftX, leftWidth);
    final center = _FlowBuilder(x: centerX, width: centerWidth);
    if (header.showBismillah && header.bismillah.content.isNotEmpty) {
      center.add(
        _contentBlock(
          id: 'header/bismillah',
          kind: LayoutBlockKind.body,
          semanticNode: header.bismillah,
          content: header.bismillah.content,
          style: _resolveStyle(
            header.bismillah.style.role ?? VisualRole.bismillah,
            override: header.bismillah.style.override,
          ),
          alignment: PaperAlign.center,
          direction: header.bismillah.direction,
          x: centerX,
          width: centerWidth,
        ),
        after: lineGap,
      );
    }
    for (var index = 0; index < header.centerColumn.length; index++) {
      final line = header.centerColumn[index];
      if (line.content.isEmpty) continue;
      center.add(
        _contentBlock(
          id: 'header/center/line/$index',
          kind: LayoutBlockKind.body,
          semanticNode: line,
          content: line.content,
          style: _resolveStyle(
            VisualRole.headerBody,
            override: headerOverride,
            bold: line.bold,
          ),
          alignment: line.alignment,
          direction: line.direction,
          x: centerX,
          width: centerWidth,
        ),
        after: lineGap,
      );
    }
    final columnHeight = <double>[left.height, center.height, right.height]
        .reduce((a, b) => a > b ? a : b);
    final height = columnHeight == 0 ? 0.0 : columnHeight + 2 * padY;
    final children = <LayoutBlock>[
      ...left.children.map((block) => _moveBlock(block, 0, padY)),
      ...center.children.map((block) => _moveBlock(block, 0, padY)),
      ...right.children.map((block) => _moveBlock(block, 0, padY)),
    ];
    final headerRect = LayoutRect.fromLTWH(_left, 0, _width, height);
    final framed = header.framed ||
        configuration.headerBorder ||
        configuration.paperSettings.headerBorder;
    return _FlowBlock(
      LayoutBlock(
        id: 'header',
        semanticNodeId: 'header',
        semanticNode: header,
        kind: LayoutBlockKind.header,
        rect: headerRect,
        lines: const <LayoutLine>[],
        children: List<LayoutBlock>.unmodifiable(children),
        decorations: framed && height > 0
            ? <LayoutDecoration>[
                LayoutDecoration(
                  id: 'header/frame',
                  semanticNodeId: 'header',
                  kind: LayoutDecorationKind.border,
                  rect: headerRect,
                  strokeWidthPt: 1,
                ),
              ]
            : const <LayoutDecoration>[],
        keepTogether: true,
      ),
      height,
    );
  }

  _FlowBlock _layoutFooter(FooterBlock footer) {
    final gutter = LayoutUnits.pxToPt(8);
    final innerWidth = (_width - 2 * gutter).clamp(0.0, _width).toDouble();
    final sideWidth = innerWidth * 0.3;
    final centerWidth = innerWidth * 0.4;
    final leftX = _left;
    final centerX = leftX + sideWidth + gutter;
    final rightX = centerX + centerWidth + gutter;
    final bodyStyle = _resolveStyle(
      VisualRole.headerBody,
      override: configuration.headerStyle,
    );
    final titleStyle = bodyStyle.copyWith(bold: true);
    final signatureGap = LayoutUnits.pxToPt(3);

    _FlowBuilder signatureFlow(
      String id,
      SignatureBlock source,
      double x,
      double width,
    ) {
      final flow = _FlowBuilder(x: x, width: width);
      flow.add(
        _nodeBlock(
          id: '$id/title',
          kind: LayoutBlockKind.body,
          semanticNode: source.title,
          nodes: <InlineNode>[source.title],
          style: titleStyle,
          alignment: PaperAlign.center,
          direction: source.direction,
          role: LayoutSemanticRole.label,
          x: x,
          width: width,
        ),
        after: signatureGap,
      );
      if (source.name.isNotEmpty) {
        flow.add(
          _contentBlock(
            id: '$id/name',
            kind: LayoutBlockKind.body,
            semanticNode: source,
            content: source.name,
            style: bodyStyle,
            alignment: PaperAlign.center,
            direction: source.direction,
            x: x,
            width: width,
          ),
        );
      }
      return flow;
    }

    final left = signatureFlow('footer/primary', footer.primary, leftX, sideWidth);
    final right = footer.secondary == null
        ? _FlowBuilder(x: rightX, width: sideWidth)
        : signatureFlow('footer/secondary', footer.secondary!, rightX, sideWidth);
    final center = _FlowBuilder(x: centerX, width: centerWidth);
    if (footer.closingPhrase != null && footer.closingPhrase!.content.isNotEmpty) {
      final phrase = footer.closingPhrase!;
      center.add(
        _contentBlock(
          id: 'footer/closingPhrase',
          kind: LayoutBlockKind.body,
          semanticNode: phrase,
          content: phrase.content,
          style: _resolveStyle(
            VisualRole.headerBody,
            override: configuration.headerStyle,
            bold: true,
          ),
          alignment: PaperAlign.center,
          direction: phrase.direction,
          x: centerX,
          width: centerWidth,
        ),
      );
    }
    final height = <double>[left.height, center.height, right.height]
        .reduce((a, b) => a > b ? a : b);
    final children = <LayoutBlock>[
      ...left.children.map((block) => _moveBlock(block, 0, (height - left.height) / 2)),
      ...center.children.map((block) => _moveBlock(block, 0, (height - center.height) / 2)),
      ...right.children.map((block) => _moveBlock(block, 0, (height - right.height) / 2)),
    ];
    return _FlowBlock(
      LayoutBlock(
        id: 'footer',
        semanticNodeId: 'footer',
        semanticNode: footer,
        kind: LayoutBlockKind.footer,
        rect: LayoutRect.fromLTWH(_left, 0, _width, height),
        lines: const <LayoutLine>[],
        children: List<LayoutBlock>.unmodifiable(children),
        keepTogether: true,
      ),
      height,
    );
  }

  _QuestionFlow _layoutQuestion(QuestionBlock question) {
    final framePadding = question.container.framed
        ? LayoutUnits.pxToPt(VisualMetrics.questionFramePaddingPx)
        : 0.0;
    final x = _left + framePadding;
    final width = (_width - 2 * framePadding).clamp(0.0, _width).toDouble();
    final flow = _FlowBuilder(x: x, width: width);
    final bodyOverride = _withoutColor(question.style.override);
    final paragraphGap = LayoutUnits.pxToPt(
      bodyOverride?.paragraphSpacing ?? VisualMetrics.elementGapPx,
    );

    if (question.category != null && question.category!.content.isNotEmpty) {
      final category = question.category!;
      flow.add(
        _contentBlock(
          id: '${question.id}/category',
          kind: LayoutBlockKind.category,
          semanticNode: category,
          content: category.content,
          style: _resolveStyle(
            category.style.role ?? VisualRole.category,
            override: category.style.override,
          ),
          alignment: question.categoryAlignment ?? category.alignment,
          direction: category.direction,
          x: x,
          width: width,
        ),
      );
    }

    final questionVerse = question.title.statement.isStandaloneQuranVerse &&
        configuration.subjectLayout.prefersQuranicFont &&
        configuration.quranFontAvailable;
    flow.add(
      _titleBlock(
        question.title,
        '${question.id}/title',
        question.direction,
        x: x,
        width: width,
        role: questionVerse ? VisualRole.verse : VisualRole.questionTitle,
        centerVerse: questionVerse,
      ),
    );

    if (question.body != null && question.body!.content.isNotEmpty) {
      final body = question.body!;
      flow.add(
        _contentBlock(
          id: '${question.id}/body',
          kind: LayoutBlockKind.body,
          semanticNode: body,
          content: body.content,
          style: _resolveStyle(
            body.style.role ?? VisualRole.questionBody,
            override: bodyOverride,
          ),
          alignment: question.bodyAlignment ?? body.alignment,
          direction: body.direction,
          x: x,
          width: width,
        ),
        before: paragraphGap,
      );
    }

    for (var index = 0; index < question.points.length; index++) {
      final point = question.points[index];
      if (!point.isPrintable) continue;
      final gap = LayoutUnits.pxToPt(
        bodyOverride?.paragraphSpacing ??
            (index == 0 ? VisualMetrics.elementGapPx : VisualMetrics.itemGapPx),
      );
      flow.add(
        _layoutPoint(point, '${question.id}/point/${point.id}', x, width,
            bodyOverride, question.direction),
        before: gap,
      );
    }
    for (final branch in question.branches) {
      if (!branch.isPrintable) continue;
      flow.add(
        _layoutBranch(branch, '${question.id}/branch/${branch.id}', x, width),
        before: paragraphGap,
      );
    }
    _reserveAttachments(flow, question.attachments, '${question.id}/attachments');
    if (question.hasDividerAfter) {
      flow.add(
        _dividerBlock('question:${question.id}', question, x: _left, width: _width),
      );
    }

    final children = <LayoutBlock>[
      for (final child in flow.children)
        _moveBlock(child, 0, framePadding),
    ];
    final height = flow.height + 2 * framePadding;
    final rootRect = LayoutRect.fromLTWH(_left, 0, _width, height);
    return _QuestionFlow(
      LayoutBlock(
        id: question.id,
        semanticNodeId: question.id,
        semanticNode: question,
        kind: LayoutBlockKind.question,
        rect: rootRect,
        lines: const <LayoutLine>[],
        children: List<LayoutBlock>.unmodifiable(children),
        decorations: question.container.framed
            ? <LayoutDecoration>[
                LayoutDecoration(
                  id: '${question.id}/frame',
                  semanticNodeId: question.id,
                  kind: LayoutDecorationKind.border,
                  rect: rootRect,
                  strokeWidthPt: 1,
                  radiusPt: 2,
                ),
              ]
            : const <LayoutDecoration>[],
        keepTogether: true,
      ),
      height,
      configuration.questionSpacing(question.id),
    );
  }

  LayoutBlock _layoutBranch(
    BranchBlock branch,
    String id,
    double parentX,
    double parentWidth,
  ) {
    final indent = LayoutUnits.pxToPt(VisualMetrics.branchIndentPx);
    final framePadding = branch.container.framed
        ? LayoutUnits.pxToPt(VisualMetrics.branchFramePaddingPx)
        : 0.0;
    final endInset = LayoutUnits.pxToPt(4);
    final branchX = parentX + indent;
    final branchWidth = (parentWidth - indent).clamp(0.0, parentWidth).toDouble();
    final contentX = branchX + framePadding;
    final contentWidth = (branchWidth - endInset - 2 * framePadding)
        .clamp(0.0, branchWidth)
        .toDouble();
    final flow = _FlowBuilder(x: contentX, width: contentWidth);
    final standaloneVerse = branch.title.statement.isStandaloneQuranVerse &&
        configuration.subjectLayout.prefersQuranicFont &&
        configuration.quranFontAvailable;
    final role = standaloneVerse ? VisualRole.verse : VisualRole.branchTitle;
    final override = branch.style.override;
    final paragraphGap = LayoutUnits.pxToPt(
      override?.paragraphSpacing ?? VisualMetrics.branchGapPx,
    );
    flow.add(
      _titleBlock(
        branch.title,
        '$id/title',
        branch.direction,
        x: contentX,
        width: contentWidth,
        role: role,
        boldLabel: true,
        centerVerse: standaloneVerse,
      ),
    );
    if (branch.body != null && branch.body!.content.isNotEmpty) {
      final body = branch.body!;
      flow.add(
        _contentBlock(
          id: '$id/body',
          kind: LayoutBlockKind.body,
          semanticNode: body,
          content: body.content,
          style: _resolveStyle(
            body.style.role ?? VisualRole.branchBody,
            override: override,
          ),
          alignment: branch.alignment ?? body.alignment,
          direction: body.direction,
          x: contentX,
          width: contentWidth,
        ),
        before: paragraphGap,
      );
    }
    for (var index = 0; index < branch.points.length; index++) {
      final point = branch.points[index];
      if (!point.isPrintable) continue;
      flow.add(
        _layoutPoint(point, '$id/point/${point.id}', contentX, contentWidth,
            override, branch.direction),
        before: LayoutUnits.pxToPt(
          override?.paragraphSpacing ??
              (index == 0 ? VisualMetrics.branchGapPx : VisualMetrics.itemGapPx),
        ),
      );
    }
    _reserveAttachments(flow, branch.attachments, '$id/attachments');
    if (branch.hasDividerAfter) {
      flow.add(_dividerBlock('branch:${branch.id}', branch, x: branchX, width: branchWidth));
    }

    final children = <LayoutBlock>[
      for (final child in flow.children)
        _moveBlock(child, 0, framePadding),
    ];
    final height = flow.height + 2 * framePadding;
    final rect = LayoutRect.fromLTWH(branchX, 0, branchWidth, height);
    return LayoutBlock(
        id: branch.id,
        semanticNodeId: branch.id,
        semanticNode: branch,
        kind: LayoutBlockKind.branch,
        rect: rect,
        lines: const <LayoutLine>[],
        children: List<LayoutBlock>.unmodifiable(children),
        decorations: branch.container.framed
            ? <LayoutDecoration>[
                LayoutDecoration(
                  id: '$id/frame',
                  semanticNodeId: branch.id,
                  kind: LayoutDecorationKind.border,
                  rect: rect,
                  strokeWidthPt: 0.8,
                  radiusPt: 2,
                ),
              ]
            : const <LayoutDecoration>[],
        keepTogether: true,
      );
  }

  LayoutBlock _layoutPoint(
    PointBlock point,
    String id,
    double parentX,
    double parentWidth,
    PaperTextStyle? ownerStyle,
    DocumentDirection direction,
  ) {
    final indent = LayoutUnits.pxToPt(VisualMetrics.pointIndentPx);
    final pointX = parentX + indent;
    final pointWidth = (parentWidth - indent).clamp(0.0, parentWidth).toDouble();
    final style = _resolveStyle(VisualRole.point, override: ownerStyle);
    final spans = <MetricSpan>[];
    final label = point.labelOrNumber;
    if (label != null) {
      spans.addAll(_nodeSpans(label, '$id/label', style.copyWith(bold: true), direction,
          LayoutSemanticRole.label));
    }
    if (point.separator != null) {
      spans.addAll(_nodeSpans(point.separator!, '$id/separator', style, direction,
          LayoutSemanticRole.separator));
    }
    if (label != null && point.content.isNotEmpty) {
      spans.add(_fixedSpacer(
        '$id/gap/label-content',
        style,
        direction,
        LayoutUnits.pxToPt(VisualMetrics.pointLabelGapPx),
        point.separator,
      ));
    }
    spans.addAll(_contentSpans(point.content, '$id/content', style, direction));
    if (point.trailer != null) {
      spans.addAll(_contentSpans(point.trailer!, '$id/trailer', style, direction));
    }
    if (point.marks != null) {
      if (point.content.isNotEmpty || point.trailer?.isNotEmpty == true) {
        spans.add(_fixedSpacer(
          '$id/gap/marks', style, direction, LayoutUnits.pxToPt(4), point.marks,
        ));
      }
      spans.addAll(_nodeSpans(
        point.marks!, '$id/marks', style, direction, LayoutSemanticRole.marks,
      ));
    }
    final flow = _FlowBuilder(x: pointX, width: pointWidth);
    flow.add(
      _paragraphBlock(
        id: '$id/line',
        kind: LayoutBlockKind.point,
        semanticNode: point,
        spans: spans,
        style: style,
        alignment: point.alignment ?? ownerStyle?.align,
        direction: point.direction == DocumentDirection.inherit ? direction : point.direction,
        width: pointWidth,
        x: pointX,
      ),
    );
    if (point.kind == PointKind.multipleChoice && point.options != null) {
      final options = point.options!.options.where((option) => option.isPrintable).toList();
      if (options.isNotEmpty) {
        flow.add(
          _layoutOptions(
            point,
            options,
            '$id/options',
            pointX + LayoutUnits.pxToPt(VisualMetrics.optionIndentPx),
            (pointWidth - LayoutUnits.pxToPt(VisualMetrics.optionIndentPx))
                .clamp(0.0, pointWidth)
                .toDouble(),
            ownerStyle,
            direction,
          ),
          before: LayoutUnits.pxToPt(VisualMetrics.optionTopGapPx),
        );
      }
    }
    final children = List<LayoutBlock>.unmodifiable(flow.children);
    return LayoutBlock(
        id: point.id,
        semanticNodeId: point.id,
        semanticNode: point,
        kind: LayoutBlockKind.point,
        rect: LayoutRect.fromLTWH(parentX, 0, parentWidth, flow.height),
        lines: const <LayoutLine>[],
        children: children,
        keepTogether: false,
      );
  }

  LayoutBlock _layoutOptions(
    PointBlock point,
    List<OptionNode> options,
    String id,
    double x,
    double width,
    PaperTextStyle? ownerStyle,
    DocumentDirection direction,
  ) {
    final spacing = LayoutUnits.pxToPt(VisualMetrics.optionWrapSpacingPx);
    final maxBox = LayoutUnits.pxToPt(VisualMetrics.optionBoxWidthPx);
    final boxWidth = maxBox.clamp(1.0, width).toDouble();
    final rowCapacity = ((width + spacing) / (boxWidth + spacing))
        .floor()
        .clamp(1, options.length)
        .toInt();
    final optionStyle = _resolveStyle(VisualRole.option, override: ownerStyle);
    final children = <LayoutBlock>[];
    var cursorY = 0.0;
    for (var start = 0; start < options.length; start += rowCapacity) {
      final end = (start + rowCapacity).clamp(0, options.length).toInt();
      final row = options.sublist(start, end);
      final rowBlocks = <LayoutBlock>[];
      var rowHeight = 0.0;
      for (var column = 0; column < row.length; column++) {
        final option = row[column];
        final cellX = direction == DocumentDirection.ltr
            ? x + column * (boxWidth + spacing)
            : x + width - boxWidth - column * (boxWidth + spacing);
        final spans = <MetricSpan>[];
        final labelStyle = optionStyle.copyWith(bold: true);
        for (var prefix = 0; prefix < option.labelPrefix.length; prefix++) {
          spans.addAll(_nodeSpans(
            option.labelPrefix[prefix], '$id/${option.id}/labelPrefix/$prefix',
            labelStyle, direction, LayoutSemanticRole.separator,
          ));
        }
        spans.addAll(_nodeSpans(
          option.label, '$id/${option.id}/label', labelStyle,
          option.direction, LayoutSemanticRole.label,
        ));
        for (var suffix = 0; suffix < option.labelSuffix.length; suffix++) {
          spans.addAll(_nodeSpans(
            option.labelSuffix[suffix], '$id/${option.id}/labelSuffix/$suffix',
            labelStyle, direction, LayoutSemanticRole.separator,
          ));
        }
        if (option.labelContent.isNotEmpty && option.content.isNotEmpty) {
          spans.add(_fixedSpacer(
            '$id/${option.id}/labelGap',
            optionStyle,
            direction,
            LayoutUnits.pxToPt(VisualMetrics.optionLabelGapPx),
            option.labelTextSeparator,
          ));
        }
        spans.addAll(_contentSpans(
          option.content, '$id/${option.id}/content', optionStyle, direction,
        ));
        rowBlocks.add(
          _paragraphBlock(
            id: '$id/${option.id}',
            kind: LayoutBlockKind.option,
            semanticNode: option,
            spans: spans,
            style: optionStyle,
            alignment: option.alignment ?? ownerStyle?.align,
            direction: option.direction == DocumentDirection.inherit
                ? direction
                : option.direction,
            width: boxWidth,
            x: cellX,
          ),
        );
        if (rowBlocks.last.rect.height > rowHeight) rowHeight = rowBlocks.last.rect.height;
      }
      children.addAll(rowBlocks.map((block) => _moveBlock(block, 0, cursorY)));
      cursorY += rowHeight;
      if (end < options.length) cursorY += LayoutUnits.pxToPt(VisualMetrics.optionRunSpacingPx);
    }
    return LayoutBlock(
        id: id,
        semanticNodeId: point.id,
        semanticNode: point.options,
        kind: LayoutBlockKind.option,
        rect: LayoutRect.fromLTWH(x, 0, width, cursorY),
        lines: const <LayoutLine>[],
        children: List<LayoutBlock>.unmodifiable(children),
        keepTogether: false,
      );
  }

  LayoutBlock _titleBlock(
    TitleParagraphBlock title,
    String id,
    DocumentDirection direction, {
    required double x,
    required double width,
    required VisualRole role,
    bool boldLabel = false,
    bool centerVerse = false,
  }) {
    final style = _resolveStyle(role, override: title.style.override);
    final labelStyle = boldLabel ? style.copyWith(bold: true) : style;
    final spans = <MetricSpan>[];
    final labelSpans = _nodeSpans(
      title.label, '$id/label', labelStyle, direction, LayoutSemanticRole.label,
    );
    spans.addAll(labelSpans);
    if (title.separator != null) {
      spans.addAll(_nodeSpans(
        title.separator!, '$id/separator', labelStyle, direction,
        LayoutSemanticRole.separator,
      ));
    }
    if (labelSpans.isNotEmpty && (title.statement.isNotEmpty || title.marks != null)) {
      spans.add(_fixedSpacer(
        '$id/gap/label-statement', style, direction,
        LayoutUnits.pxToPt(VisualMetrics.titleGapPx),
      ));
    }
    spans.addAll(_contentSpans(title.statement, '$id/statement', style, direction));
    if (title.marks != null) {
      if (title.statement.isNotEmpty) {
        spans.add(_fixedSpacer(
          '$id/gap/statement-marks', style, direction,
          LayoutUnits.pxToPt(VisualMetrics.titleGapPx),
        ));
      }
      spans.addAll(_nodeSpans(
        title.marks!, '$id/marks', style, direction, LayoutSemanticRole.marks,
      ));
    }
    return _paragraphBlock(
      id: id,
      kind: LayoutBlockKind.title,
      semanticNode: title,
      spans: spans,
      style: style,
      alignment: centerVerse ? PaperAlign.center : title.alignment,
      direction: title.direction == DocumentDirection.inherit ? direction : title.direction,
      width: width,
      x: x,
    );
  }

  LayoutBlock _contentBlock({
    required String id,
    required LayoutBlockKind kind,
    required Object semanticNode,
    required InlineContent content,
    required LayoutTextStyle style,
    required PaperAlign? alignment,
    required DocumentDirection direction,
    required double x,
    required double width,
  }) {
    final spans = _contentSpans(content, '$id/content', style, direction);
    final segments = <List<MetricSpan>>[];
    var current = <MetricSpan>[];
    for (final span in spans) {
      if (span.isBlockMath) {
        if (current.isNotEmpty) segments.add(current);
        segments.add(<MetricSpan>[span]);
        current = <MetricSpan>[];
      } else {
        current.add(span);
      }
    }
    if (current.isNotEmpty) segments.add(current);
    if (segments.isEmpty) {
      return _paragraphBlock(
        id: id,
        kind: kind,
        semanticNode: semanticNode,
        spans: const <MetricSpan>[],
        style: style,
        alignment: alignment,
        direction: direction,
        width: width,
        x: x,
      );
    }
    if (segments.length == 1 && !segments.single.single.isBlockMath) {
      return _paragraphBlock(
        id: id,
        kind: kind,
        semanticNode: semanticNode,
        spans: segments.single,
        style: style,
        alignment: alignment,
        direction: direction,
        width: width,
        x: x,
      );
    }
    final flow = _FlowBuilder(x: x, width: width);
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final isBlockMath = segment.length == 1 && segment.single.isBlockMath;
      flow.add(
        _paragraphBlock(
          id: isBlockMath ? '$id/block-math/$index' : (index == 0 ? id : '$id/segment/$index'),
          kind: kind,
          semanticNode: semanticNode,
          spans: segment,
          style: style,
          alignment: isBlockMath ? PaperAlign.center : alignment,
          direction: direction,
          width: width,
          x: x,
        ),
        before: isBlockMath ? LayoutUnits.pxToPt(4) : 0,
        after: isBlockMath ? LayoutUnits.pxToPt(4) : 0,
      );
    }
    return LayoutBlock(
      id: id,
      semanticNodeId: id,
      semanticNode: semanticNode,
      kind: kind,
      rect: LayoutRect.fromLTWH(x, 0, width, flow.height),
      lines: const <LayoutLine>[],
      children: List<LayoutBlock>.unmodifiable(flow.children),
      keepTogether: false,
    );
  }

  LayoutBlock _paragraphBlock({
    required String id,
    required LayoutBlockKind kind,
    required Object? semanticNode,
    required List<MetricSpan> spans,
    required LayoutTextStyle style,
    required PaperAlign? alignment,
    required DocumentDirection direction,
    required double width,
    required double x,
  }) {
    if (spans.isEmpty) {
      return LayoutBlock(
        id: id,
        semanticNodeId: id,
        semanticNode: semanticNode,
        kind: kind,
        rect: LayoutRect.fromLTWH(x, 0, width, 0),
        lines: const <LayoutLine>[],
      );
    }
    final resolvedAlignment = alignment ?? style.alignment;
    final paragraph = fontMetrics.layoutParagraph(
      spans: spans,
      width: width,
      direction: direction,
      alignment: resolvedAlignment,
      resolveJustification: true,
    );
    final lines = <LayoutLine>[];
    for (final measured in paragraph.lines) {
      final fragments = <({MetricSpan span, MeasuredRunFragment fragment})>[];
      for (final fragment in measured.fragments) {
        if (fragment.spanIndex >= 0 && fragment.spanIndex < spans.length) {
          fragments.add((span: spans[fragment.spanIndex], fragment: fragment));
        }
      }
      fragments.sort((a, b) {
        final dx = a.fragment.x.compareTo(b.fragment.x);
        if (dx != 0) return dx;
        return a.span.logicalIndex.compareTo(b.span.logicalIndex);
      });
      final runs = <LayoutRun>[];
      for (var visualIndex = 0; visualIndex < fragments.length; visualIndex++) {
        final item = fragments[visualIndex];
        final fragment = item.fragment;
        final run = LayoutRun(
          id: '${item.span.semanticNodeId}/line/${measured.index}/fragment/$visualIndex',
          semanticNodeId: item.span.semanticNodeId,
          semanticNode: item.span.semanticNode,
          contentKind: item.span.contentKind,
          semanticRole: item.span.semanticRole,
          text: fragment.text,
          x: x + fragment.x,
          advance: fragment.width,
          width: fragment.width,
          height: item.span.mathBox?.heightPt ?? fragment.height,
          baselineOffset: item.span.mathBox?.baselinePt ?? fragment.baselineOffset,
          direction: fragment.direction == DocumentDirection.inherit
              ? direction
              : fragment.direction,
          style: item.span.style,
          logicalIndex: item.span.logicalIndex * 1000000 + fragment.startOffset,
          visualIndex: visualIndex,
          mathBox: item.span.mathBox,
          measurementSource: item.span.mathBox?.source ??
              (item.span.isMath ? 'fallbackEstimate' : 'fontMetrics'),
        );
        runs.add(run);
      }
      final logicalRuns = List<LayoutRun>.of(runs)
        ..sort((a, b) => a.logicalIndex.compareTo(b.logicalIndex));
      lines.add(
        LayoutLine(
          id: '$id/line/${measured.index}',
          semanticNodeId: id,
          semanticNode: semanticNode,
          paragraphIndex: _paragraphSerial,
          lineIndex: measured.index,
          rect: LayoutRect.fromLTWH(x, measured.top, width, measured.height),
          baseline: measured.baseline,
          ascent: measured.ascent,
          descent: measured.descent,
          leading: measured.leading,
          direction: direction,
          alignment: resolvedAlignment,
          runs: List<LayoutRun>.unmodifiable(runs),
          logicalRunIds: List<String>.unmodifiable(logicalRuns.map((run) => run.id)),
          visualRunIds: List<String>.unmodifiable(runs.map((run) => run.id)),
          naturalWidth: measured.naturalWidth,
          resolvedWidth: measured.resolvedWidth,
          isJustified: measured.isJustified,
          justificationOpportunityCount: measured.justificationOpportunityCount,
          extraSpacePerOpportunity: measured.extraSpacePerOpportunity,
        ),
      );
    }
    _paragraphSerial++;
    return LayoutBlock(
      id: id,
      semanticNodeId: id,
      semanticNode: semanticNode,
      kind: kind,
      rect: LayoutRect.fromLTWH(x, 0, width, paragraph.height),
      lines: List<LayoutLine>.unmodifiable(lines),
    );
  }

  List<MetricSpan> _contentSpans(
    InlineContent content,
    String path,
    LayoutTextStyle style,
    DocumentDirection direction,
  ) {
    final spans = <MetricSpan>[];
    for (var index = 0; index < content.nodes.length; index++) {
      spans.addAll(_nodeSpans(
        content.nodes[index],
        '$path/$index',
        style,
        direction,
        LayoutSemanticRole.text,
      ));
    }
    return spans;
  }

  LayoutBlock _nodeBlock({
    required String id,
    required LayoutBlockKind kind,
    required Object? semanticNode,
    required List<InlineNode> nodes,
    required LayoutTextStyle style,
    required PaperAlign? alignment,
    required DocumentDirection direction,
    required LayoutSemanticRole role,
    required double x,
    required double width,
  }) {
    final spans = <MetricSpan>[];
    for (var index = 0; index < nodes.length; index++) {
      spans.addAll(_nodeSpans(nodes[index], '$id/$index', style, direction, role));
    }
    return _paragraphBlock(
      id: id,
      kind: kind,
      semanticNode: semanticNode,
      spans: spans,
      style: style,
      alignment: alignment,
      direction: direction,
      width: width,
      x: x,
    );
  }

  List<MetricSpan> _nodeSpans(
    InlineNode node,
    String path,
    LayoutTextStyle style,
    DocumentDirection direction,
    LayoutSemanticRole semanticRole,
  ) {
    if (node is LabelNode) {
      final spans = <MetricSpan>[];
      for (var index = 0; index < node.content.nodes.length; index++) {
        spans.addAll(_nodeSpans(
          node.content.nodes[index],
          '$path/content/$index',
          style,
          node.direction == DocumentDirection.inherit ? direction : node.direction,
          LayoutSemanticRole.label,
        ));
      }
      return spans;
    }
    if (node is MarksNode) {
      return <MetricSpan>[
        ..._nodeSpans(node.opening, '$path/opening', style, direction, LayoutSemanticRole.marks),
        ..._nodeSpans(node.number, '$path/number', style, direction, LayoutSemanticRole.marks),
        ..._nodeSpans(node.numberUnitGap, '$path/numberUnitGap', style, direction, LayoutSemanticRole.marks),
        ..._nodeSpans(node.unit, '$path/unit', style, direction, LayoutSemanticRole.marks),
        ..._nodeSpans(node.closing, '$path/closing', style, direction, LayoutSemanticRole.marks),
      ];
    }
    if (node is NumberNode) {
      return <MetricSpan>[
        _metricSpan(
          id: path,
          node: node,
          text: node.displayText,
          kind: LayoutContentKind.number,
          role: semanticRole == LayoutSemanticRole.marks
              ? LayoutSemanticRole.marks
              : LayoutSemanticRole.number,
          style: style,
          direction: _nodeDirection(node.direction, direction),
        ),
      ];
    }
    if (node is SeparatorNode) {
      return <MetricSpan>[
        _metricSpan(
          id: path,
          node: node,
          text: node.text,
          kind: LayoutContentKind.separator,
          role: semanticRole,
          style: style,
          direction: _nodeDirection(node.direction, direction),
        ),
      ];
    }
    if (node is RichRunNode) {
      final quranFont = node is QuranNode && configuration.quranFontAvailable
          ? node.fontIntent
          : null;
      final runStyle = _mergeRunStyle(style, node.run.style, quranFont: quranFont);
      final kind = switch (node.run.kind) {
        VisualRunKind.text => _contentKindForRole(semanticRole),
        VisualRunKind.math => LayoutContentKind.math,
        VisualRunKind.quran => LayoutContentKind.quran,
      };
      final mathBox = node.run.isMath ? mathMetrics[path] : null;
      return <MetricSpan>[
        _metricSpan(
          id: path,
          node: node,
          text: node.run.text,
          kind: kind,
          role: semanticRole,
          style: runStyle,
          direction: _nodeDirection(node.direction, direction),
          mathBox: mathBox,
          isBlockMath: node.run.isBlockMath,
        ),
      ];
    }
    final spans = <MetricSpan>[];
    var index = 0;
    for (final run in node.visualRuns) {
      final runKind = switch (run.kind) {
        VisualRunKind.text => _contentKindForRole(semanticRole),
        VisualRunKind.math => LayoutContentKind.math,
        VisualRunKind.quran => LayoutContentKind.quran,
      };
      final runStyle = _mergeRunStyle(style, run.style);
      spans.add(_metricSpan(
        id: '$path/run/${index++}',
        node: node,
        text: run.text,
        kind: runKind,
        role: semanticRole,
        style: runStyle,
        direction: _nodeDirection(node.direction, direction),
        mathBox: run.isMath ? mathMetrics['$path/run/${index - 1}'] : null,
        isBlockMath: run.isBlockMath,
      ));
    }
    return spans;
  }

  LayoutContentKind _contentKindForRole(LayoutSemanticRole role) => switch (role) {
        LayoutSemanticRole.text => LayoutContentKind.text,
        LayoutSemanticRole.label => LayoutContentKind.label,
        LayoutSemanticRole.number => LayoutContentKind.number,
        LayoutSemanticRole.separator => LayoutContentKind.separator,
        LayoutSemanticRole.marks => LayoutContentKind.marks,
        LayoutSemanticRole.image => LayoutContentKind.image,
      };

  MetricSpan _metricSpan({
    required String id,
    required InlineNode? node,
    required String text,
    required LayoutContentKind kind,
    required LayoutSemanticRole role,
    required LayoutTextStyle style,
    required DocumentDirection direction,
    LayoutMathBox? mathBox,
    bool isBlockMath = false,
  }) =>
      MetricSpan(
        semanticNodeId: id,
        semanticNode: node,
        text: text,
        contentKind: kind,
        semanticRole: role,
        style: style,
        direction: direction,
        logicalIndex: _logicalRunSerial++,
        mathBox: mathBox,
        isBlockMath: isBlockMath,
      );

  MetricSpan _fixedSpacer(
    String id,
    LayoutTextStyle style,
    DocumentDirection direction,
    double widthPt, [
    InlineNode? semanticNode,
  ]) =>
      MetricSpan(
        semanticNodeId: id,
        semanticNode: semanticNode,
        text: '',
        contentKind: LayoutContentKind.separator,
        semanticRole: LayoutSemanticRole.separator,
        style: style,
        direction: direction,
        logicalIndex: _logicalRunSerial++,
        fixedAdvancePt: widthPt,
      );

  LayoutBlock _dividerBlock(
    String sourceId,
    Object owner, {
    required double x,
    required double width,
  }) {
    final input = configuration.dividers[sourceId];
    final fraction = input?.widthFraction ?? 1.0;
    final thickness = input?.thicknessPt ?? LayoutUnits.pxToPt(VisualMetrics.dividerThicknessPx);
    final before = input?.spacingBeforePt ?? LayoutUnits.pxToPt(6);
    final after = input?.spacingAfterPt ?? LayoutUnits.pxToPt(6);
    final ruleWidth = (width * fraction).clamp(0.0, width).toDouble();
    final ruleX = x + (width - ruleWidth) / 2;
    final blockHeight = before + thickness + after;
    final rect = LayoutRect.fromLTWH(ruleX, before, ruleWidth, thickness);
    return LayoutBlock(
      id: '$sourceId/divider',
      semanticNodeId: sourceId,
      semanticNode: owner,
      kind: LayoutBlockKind.divider,
      rect: LayoutRect.fromLTWH(x, 0, width, blockHeight),
      lines: const <LayoutLine>[],
      decorations: <LayoutDecoration>[
        LayoutDecoration(
          id: '$sourceId/divider/rule',
          semanticNodeId: sourceId,
          kind: LayoutDecorationKind.divider,
          rect: rect,
          strokeWidthPt: thickness,
        ),
      ],
    );
  }

  void _reserveAttachments(
    _FlowBuilder flow,
    AttachmentBlock? attachments,
    String id,
  ) {
    if (attachments == null) return;
    var reservePt = 0.0;
    for (final element in attachments.elements) {
      final input = configuration.floatingElements[element.id];
      if (input == null || input.flowReserveHeightPx <= 0) continue;
      final height = LayoutUnits.pxToPt(input.flowReserveHeightPx);
      if (height > reservePt) reservePt = height;
    }
    if (reservePt <= flow.height) return;
    final height = reservePt - flow.height;
    flow.add(
      LayoutBlock(
        id: id,
        semanticNodeId: id,
        semanticNode: attachments,
        kind: LayoutBlockKind.attachment,
        rect: LayoutRect.fromLTWH(flow.x, 0, flow.width, height),
        lines: const <LayoutLine>[],
      ),
    );
  }

  _Pagination _paginate(List<_QuestionFlow> questions) {
    final pages = <_PageState>[_PageState(0, null)];
    final footerReserve = _footer.height > 0 ? _footer.height + _footerGap : 0.0;
    final headerReserve = _header.height > 0 ? _header.height + _headerGap : 0.0;

    for (var index = 0; index < questions.length; index++) {
      final question = questions[index];
      final isFinalQuestion = index == questions.length - 1;
      var page = pages.last;
      final normalCapacity = (_contentHeight - (page.index == 0 ? headerReserve : 0))
          .clamp(0.0, _contentHeight)
          .toDouble();
      final finalCapacity = (_contentHeight -
              (page.index == 0 ? headerReserve : 0) -
              (isFinalQuestion ? footerReserve : 0))
          .clamp(0.0, _contentHeight)
          .toDouble();
      final gap = page.questions.isEmpty ? 0.0 : page.questions.last.flow.spacingAfterPt;
      final needed = page.usedHeight + gap + question.height;
      final currentCapacity = isFinalQuestion ? finalCapacity : normalCapacity;

      if (needed <= currentCapacity + _epsilon) {
        page.add(question, gap);
        continue;
      }

      final newPageCapacity = _contentHeight - (isFinalQuestion ? footerReserve : 0);
      final canKeepWholeOnFreshPage = question.height <= newPageCapacity + _epsilon;
      if (canKeepWholeOnFreshPage) {
        final reason = isFinalQuestion
            ? PageBreakReason.headerFooterReservation
            : (question.height > normalCapacity ? PageBreakReason.naturalOverflow : PageBreakReason.keepTogether);
        page = _newPage(pages, reason);
        page.add(question, 0);
        continue;
      }

      if (page.questions.isNotEmpty) {
        page = _newPage(pages, PageBreakReason.forcedSplit);
      }
      _appendSplitQuestion(
        pages,
        page,
        question,
        isFinalQuestion: isFinalQuestion,
        headerReserve: headerReserve,
        footerReserve: isFinalQuestion ? footerReserve : 0,
      );
    }
    return _Pagination(pages);
  }

  static const double _epsilon = 0.01;

  _PageState _newPage(List<_PageState> pages, PageBreakReason reason) {
    final state = _PageState(pages.length, reason);
    pages.add(state);
    return state;
  }

  void _appendSplitQuestion(
    List<_PageState> pages,
    _PageState firstPage,
    _QuestionFlow question, {
    required bool isFinalQuestion,
    required double headerReserve,
    required double footerReserve,
  }) {
    final allLines = _flattenLines(<LayoutBlock>[question.block])..sort(_compareLines);
    if (allLines.isEmpty) {
      final capacity = (_contentHeight -
              (firstPage.index == 0 ? headerReserve : 0) -
              (isFinalQuestion ? footerReserve : 0))
          .clamp(0.0, _contentHeight)
          .toDouble();
      final scale = configuration.scaleOversizedBlocks && question.height > capacity && question.height > 0
          ? (capacity / question.height).clamp(0.01, 1.0).toDouble()
          : 1.0;
      final scaledBlock = scale == 1 ? question.block : _scaleBlock(question.block, scale);
      final scaledFlow = question.copyWithBlock(scaledBlock);
      firstPage.add(scaledFlow, 0, reason: PageBreakReason.forcedSplit);
      firstPage.scaleFactor = scale;
      return;
    }
    final groups = <List<LayoutLine>>[];
    var lineStart = 0;
    var currentPageIndex = firstPage.index;
    while (lineStart < allLines.length) {
      final pageHasHeader = currentPageIndex == 0;
      final normalCapacity = (_contentHeight - (pageHasHeader ? headerReserve : 0))
          .clamp(0.0, _contentHeight)
          .toDouble();
      final lastCapacity = (_contentHeight -
              (pageHasHeader ? headerReserve : 0) -
              (isFinalQuestion ? footerReserve : 0))
          .clamp(0.0, _contentHeight)
          .toDouble();
      final firstTop = allLines[lineStart].rect.top;
      final remainingBottom = allLines.last.rect.bottom;
      final remainingHeight = remainingBottom - firstTop;
      final isFinalChunk = remainingHeight <= lastCapacity + _epsilon;
      final capacity = isFinalChunk ? lastCapacity : normalCapacity;
      var end = lineStart;
      while (end < allLines.length &&
          allLines[end].rect.bottom - firstTop <= capacity + _epsilon) {
        end++;
      }
      if (end == lineStart) end++;
      groups.add(allLines.sublist(lineStart, end));
      lineStart = end;
      if (lineStart < allLines.length) currentPageIndex++;
    }

    var page = firstPage;
    for (var fragmentIndex = 0; fragmentIndex < groups.length; fragmentIndex++) {
      if (fragmentIndex > 0) {
        page = _newPage(pages, PageBreakReason.forcedSplit);
      }
      final fragment = _sliceQuestion(
        question,
        groups[fragmentIndex],
        fragmentIndex,
        groups.length,
      );
      page.add(
        fragment,
        0,
        reason: fragmentIndex == 0 ? null : PageBreakReason.forcedSplit,
      );
    }
  }

  _QuestionFlow _sliceQuestion(
    _QuestionFlow question,
    List<LayoutLine> lines,
    int fragmentIndex,
    int fragmentCount,
  ) {
    final firstTop = lines.first.rect.top;
    final lastBottom = lines.last.rect.bottom;
    final selectedIds = lines.map((line) => line.id).toSet();
    final children = <LayoutBlock>[];
    for (final child in question.block.children) {
      final slice = _sliceBlock(
        child,
        selectedIds,
        -firstTop,
        firstTop,
        lastBottom,
      );
      if (slice != null && (slice.lines.isNotEmpty || slice.rect.height > 0)) {
        children.add(slice);
      }
    }
    final fragmentHeight = (lastBottom - firstTop).clamp(0.0, double.infinity).toDouble();
    final rect = LayoutRect.fromLTWH(_left, 0, _width, fragmentHeight);
    return question.copyWithBlock(
      LayoutBlock(
        id: '${question.block.semanticNodeId}/fragment/$fragmentIndex',
        semanticNodeId: question.block.semanticNodeId,
        semanticNode: question.block.semanticNode,
        kind: LayoutBlockKind.question,
        rect: rect,
        lines: const <LayoutLine>[],
        children: List<LayoutBlock>.unmodifiable(children),
        decorations: question.block.decorations
            .map((decoration) => LayoutDecoration(
                  id: decoration.id,
                  semanticNodeId: decoration.semanticNodeId,
                  kind: decoration.kind,
                  rect: LayoutRect.fromLTWH(
                    decoration.rect.left,
                    0,
                    decoration.rect.width,
                    fragmentHeight,
                  ),
                  strokeWidthPt: decoration.strokeWidthPt,
                  colorArgb: decoration.colorArgb,
                  radiusPt: decoration.radiusPt,
                ))
            .toList(growable: false),
        split: LayoutSplitMetadata(
          fragmentIndex: fragmentIndex,
          fragmentCount: fragmentCount,
          firstLineIndex: lines.first.lineIndex,
          lastLineIndexExclusive: lines.last.lineIndex + 1,
          continuesFromPrevious: fragmentIndex > 0,
          continuesOnNext: fragmentIndex + 1 < fragmentCount,
        ),
        keepTogether: true,
        continuation: fragmentIndex > 0,
      ),
      spacingAfterPt: fragmentIndex + 1 == fragmentCount ? question.spacingAfterPt : 0,
    );
  }

  LayoutBlock? _sliceBlock(
    LayoutBlock source,
    Set<String> selectedIds,
    double dy,
    double sliceTop,
    double sliceBottom,
  ) {
    if (source.lines.isEmpty && source.children.isEmpty) {
      if (source.rect.height <= 0) return null;
      final center = source.rect.top + source.rect.height / 2;
      if (center < sliceTop || center >= sliceBottom) return null;
      return _moveBlock(source, 0, dy);
    }
    final ownLines = source.lines.where((line) => selectedIds.contains(line.id)).toList();
    final children = <LayoutBlock>[];
    for (final child in source.children) {
      final slice = _sliceBlock(child, selectedIds, dy, sliceTop, sliceBottom);
      if (slice != null && (slice.lines.isNotEmpty || slice.children.isNotEmpty)) {
        children.add(slice);
      }
    }
    if (ownLines.isEmpty && children.isEmpty) return null;
    final movedOwnLines = <LayoutLine>[for (final line in ownLines) _moveLine(line, 0, dy)];
    final allLines = <LayoutLine>[...movedOwnLines, ..._flattenLines(children)]
      ..sort(_compareLines);
    final top = allLines.isEmpty ? source.rect.top + dy : allLines.first.rect.top;
    final bottom = allLines.isEmpty ? top : allLines.last.rect.bottom;
    final rect = LayoutRect.fromLTWH(source.rect.left, top, source.rect.width, bottom - top);
    final decorations = source.kind == LayoutBlockKind.branch && source.decorations.isNotEmpty
        ? source.decorations
            .map((decoration) => LayoutDecoration(
                  id: decoration.id,
                  semanticNodeId: decoration.semanticNodeId,
                  kind: decoration.kind,
                  rect: rect,
                  strokeWidthPt: decoration.strokeWidthPt,
                  colorArgb: decoration.colorArgb,
                  radiusPt: decoration.radiusPt,
                ))
            .toList(growable: false)
        : source.decorations;
    return LayoutBlock(
      id: source.id,
      semanticNodeId: source.semanticNodeId,
      semanticNode: source.semanticNode,
      kind: source.kind,
      rect: rect,
      lines: List<LayoutLine>.unmodifiable(movedOwnLines),
      children: List<LayoutBlock>.unmodifiable(children),
      decorations: decorations,
      split: source.split,
      breakReason: source.breakReason,
      scaleFactor: source.scaleFactor,
      keepTogether: source.keepTogether,
      continuation: source.continuation,
    );
  }

  List<LayoutFloatPlacement> _placeFloatingElements(
    Map<String, ({int page, double top})> pageOfSemanticNode,
    int pageCount,
  ) {
    final refs = <FloatingElementReference>[
      ...document.floatingElements?.elements ?? const <FloatingElementReference>[],
      for (final question in document.questions) ...<FloatingElementReference>[
        ...question.attachments?.elements ?? const <FloatingElementReference>[],
        for (final branch in question.branches)
          ...branch.attachments?.elements ?? const <FloatingElementReference>[],
      ],
    ];
    final seen = <String>{};
    final result = <LayoutFloatPlacement>[];
    for (final reference in refs) {
      if (!seen.add(reference.id)) continue;
      final input = configuration.floatingElements[reference.id];
      if (input == null) {
        result.add(
          LayoutFloatPlacement(
            semanticNodeId: reference.id,
            reference: reference,
            policy: reference.ownerQuestionId == null
                ? FloatAnchorPolicy.pageAnchored
                : FloatAnchorPolicy.contentAreaAnchored,
            pageIndex: 0,
            rect: const LayoutRect.fromLTWH(0, 0, 0, 0),
            deferredReason: 'source geometry not supplied to LayoutEngine',
          ),
        );
        continue;
      }
      // Legacy attachment dx/dy is anchored to its owning question's content
      // edge, even when the semantic reference also names a branch.
      final ownerId = reference.ownerQuestionId ?? input.ownerQuestionId;
      final owner = ownerId == null ? null : pageOfSemanticNode[ownerId];
      if (ownerId != null && owner == null) {
        result.add(
          LayoutFloatPlacement(
            semanticNodeId: reference.id,
            reference: reference,
            policy: FloatAnchorPolicy.contentAreaAnchored,
            pageIndex: 0,
            rect: const LayoutRect.fromLTWH(0, 0, 0, 0),
            deferredReason: 'owner question has no printable page',
          ),
        );
        continue;
      }
      final pageIndex = owner?.page ??
          input.pageIndex.clamp(0, (pageCount - 1).clamp(0, 100000)).toInt();
      final width = LayoutUnits.pxToPt(input.widthPx);
      final height = LayoutUnits.pxToPt(input.heightPx);
      final dx = LayoutUnits.pxToPt(input.dxPx);
      final dy = LayoutUnits.pxToPt(input.dyPx);
      final edge = owner == null ? dx : _left + dx;
      final physicalLeft = _direction == DocumentDirection.rtl
          ? _pageWidth - edge - width
          : edge;
      final top = owner == null ? dy : owner.top + dy;
      final lines = _layoutFloatLabel(reference, input, physicalLeft, top, width);
      result.add(
        LayoutFloatPlacement(
          semanticNodeId: reference.id,
          reference: reference,
          policy: owner == null
              ? FloatAnchorPolicy.pageAnchored
              : FloatAnchorPolicy.contentAreaAnchored,
          pageIndex: pageIndex,
          rect: LayoutRect.fromLTWH(physicalLeft, top, width, height),
          rotationDegrees: input.rotationDegrees,
          strokeWidthPt: input.strokeWidthPt,
          framed: input.framed,
          labelLines: List<LayoutLine>.unmodifiable(lines),
        ),
      );
    }
    return result;
  }

  List<LayoutLine> _layoutFloatLabel(
    FloatingElementReference reference,
    FloatingLayoutInput input,
    double left,
    double top,
    double width,
  ) {
    final content = reference.label;
    if (content == null ||
        (reference.kind != FloatingReferenceKind.textBox &&
            reference.kind != FloatingReferenceKind.formula)) {
      return const <LayoutLine>[];
    }
    final padding = LayoutUnits.pxToPt(4);
    final style = reference.kind == FloatingReferenceKind.formula
        ? LayoutTextStyle(
            font: configuration.defaultFont,
            fontSizePt: LayoutUnits.pxToPt(40),
            lineHeightFactor: 1.2,
          )
        : _resolveStyle(VisualRole.questionBody, override: input.textStyle);
    final spans = _contentSpans(content, 'float/${reference.id}/label', style, _direction);
    final block = _paragraphBlock(
      id: 'float/${reference.id}/label',
      kind: LayoutBlockKind.generic,
      semanticNode: reference,
      spans: spans,
      style: style,
      alignment: PaperAlign.start,
      direction: _direction,
      width: (width - 2 * padding).clamp(1.0, width).toDouble(),
      x: left + padding,
    );
    return <LayoutLine>[
      for (final line in block.lines) _moveLine(line, 0, top + padding),
    ];
  }

  LayoutTextStyle _resolveStyle(
    VisualRole role, {
    PaperTextStyle? override,
    bool? bold,
  }) {
    final style = ExamTypography.resolve(
      role,
      settings: configuration.paperSettings,
      layout: configuration.subjectLayout,
      override: override,
      bold: bold,
    );
    return LayoutTextStyle(
      font: style.font,
      fontSizePt: style.fontSizePt,
      lineHeightFactor: style.lineHeight,
      bold: style.bold,
      italic: style.italic,
      underline: style.underline,
      colorArgb: style.color,
      letterSpacingPt: style.letterSpacingPt,
      alignment: style.align,
    );
  }

  LayoutTextStyle _mergeRunStyle(
    LayoutTextStyle base,
    VisualRunStyle? extra, {
    PaperFont? quranFont,
  }) =>
      LayoutTextStyle(
        font: extra?.font ?? quranFont ?? base.font,
        fontSizePt: extra?.fontSizePt ?? base.fontSizePt,
        lineHeightFactor: base.lineHeightFactor,
        bold: extra?.bold ?? base.bold,
        italic: extra?.italic ?? base.italic,
        underline: extra?.underline ?? base.underline,
        colorArgb: extra?.colorArgb ?? base.colorArgb,
        letterSpacingPt: base.letterSpacingPt,
        alignment: base.alignment,
        baselineShiftPt: extra?.baselineShiftPt ?? base.baselineShiftPt,
      );

  PaperTextStyle? _withoutColor(PaperTextStyle? style) =>
      style?.copyWith(color: () => null);

  DocumentDirection _resolveDirection(DocumentDirection direction) =>
      direction == DocumentDirection.ltr || direction == DocumentDirection.rtl
          ? direction
          : (configuration.subjectLayout.isLtr
              ? DocumentDirection.ltr
              : DocumentDirection.rtl);

  DocumentDirection _nodeDirection(
    DocumentDirection source,
    DocumentDirection fallback,
  ) =>
      source == DocumentDirection.auto || source == DocumentDirection.inherit
          ? fallback
          : source;

  List<LayoutLine> _flattenLines(Iterable<LayoutBlock> blocks) => <LayoutLine>[
        for (final block in blocks) ...block.lines,
        for (final block in blocks) ..._flattenLines(block.children),
      ];

  static int _compareLines(LayoutLine a, LayoutLine b) {
    final y = a.rect.top.compareTo(b.rect.top);
    if (y != 0) return y;
    return a.rect.left.compareTo(b.rect.left);
  }
}

class _FlowBuilder {
  _FlowBuilder({required this.x, required this.width});

  final double x;
  final double width;
  final List<LayoutBlock> children = <LayoutBlock>[];
  double height = 0;

  void add(LayoutBlock block, {double before = 0, double after = 0}) {
    height += before;
    children.add(_moveBlock(block, 0, height));
    height += block.rect.height + after;
  }
}

class _FlowBlock {
  const _FlowBlock(this.block, this.height);

  final LayoutBlock block;
  final double height;
}

class _QuestionFlow {
  const _QuestionFlow(this.block, this.height, this.spacingAfterPt);

  final LayoutBlock block;
  final double height;
  final double spacingAfterPt;

  _QuestionFlow copyWithBlock(
    LayoutBlock next, {
    double? spacingAfterPt,
  }) =>
      _QuestionFlow(next, next.rect.height, spacingAfterPt ?? this.spacingAfterPt);
}

class _PageQuestion {
  const _PageQuestion(this.flow, this.topInBody, this.breakReason);

  final _QuestionFlow flow;
  final double topInBody;
  final PageBreakReason? breakReason;
}

class _PageState {
  _PageState(this.index, this.breakReason);

  final int index;
  final PageBreakReason? breakReason;
  final List<_PageQuestion> questions = <_PageQuestion>[];
  double usedHeight = 0;
  double scaleFactor = 1;

  void add(_QuestionFlow flow, double gap, {PageBreakReason? reason}) {
    final top = usedHeight + gap;
    questions.add(_PageQuestion(flow, top, reason));
    usedHeight = top + flow.height;
  }
}

class _Pagination {
  const _Pagination(this.pages);

  final List<_PageState> pages;
}

LayoutBlock _moveBlock(
  LayoutBlock block,
  double dx,
  double dy, {
  String? id,
  PageBreakReason? breakReason,
}) =>
    LayoutBlock(
      id: id ?? block.id,
      semanticNodeId: block.semanticNodeId,
      semanticNode: block.semanticNode,
      kind: block.kind,
      rect: block.rect.translate(dx, dy),
      lines: List<LayoutLine>.unmodifiable(
        block.lines.map((line) => _moveLine(line, dx, dy)),
      ),
      children: List<LayoutBlock>.unmodifiable(
        block.children.map((child) => _moveBlock(child, dx, dy)),
      ),
      decorations: List<LayoutDecoration>.unmodifiable(
        block.decorations.map((decoration) => LayoutDecoration(
              id: decoration.id,
              semanticNodeId: decoration.semanticNodeId,
              kind: decoration.kind,
              rect: decoration.rect.translate(dx, dy),
              strokeWidthPt: decoration.strokeWidthPt,
              colorArgb: decoration.colorArgb,
              radiusPt: decoration.radiusPt,
            )),
      ),
      split: block.split,
      breakReason: breakReason ?? block.breakReason,
      scaleFactor: block.scaleFactor,
      keepTogether: block.keepTogether,
      continuation: block.continuation,
    );

LayoutBlock _scaleBlock(
  LayoutBlock block,
  double factor, {
  double? originX,
  double? originY,
}) {
  final scaleOriginX = originX ?? block.rect.left;
  final scaleOriginY = originY ?? block.rect.top;
  LayoutRect scaleRect(LayoutRect rect) => LayoutRect.fromLTWH(
        scaleOriginX + (rect.left - scaleOriginX) * factor,
        scaleOriginY + (rect.top - scaleOriginY) * factor,
        rect.width * factor,
        rect.height * factor,
      );
  LayoutTextStyle scaleStyle(LayoutTextStyle style) => style.copyWith(
        fontSizePt: style.fontSizePt * factor,
        lineHeightFactor: style.lineHeightFactor,
        letterSpacingPt: () => style.letterSpacingPt == null
            ? null
            : style.letterSpacingPt! * factor,
        baselineShiftPt: style.baselineShiftPt * factor,
      );
  LayoutMathBox? scaleMath(LayoutMathBox? box) => box == null
      ? null
      : LayoutMathBox(
          widthPt: box.widthPt * factor,
          heightPt: box.heightPt * factor,
          baselinePt: box.baselinePt == null ? null : box.baselinePt! * factor,
          source: box.source,
        );
  LayoutRun scaleRun(LayoutRun run) => LayoutRun(
        id: run.id,
        semanticNodeId: run.semanticNodeId,
        semanticNode: run.semanticNode,
        contentKind: run.contentKind,
        semanticRole: run.semanticRole,
        text: run.text,
        x: scaleOriginX + (run.x - scaleOriginX) * factor,
        advance: run.advance * factor,
        width: run.width * factor,
        height: run.height * factor,
        baselineOffset: run.baselineOffset * factor,
        direction: run.direction,
        style: scaleStyle(run.style),
        logicalIndex: run.logicalIndex,
        visualIndex: run.visualIndex,
        mathBox: scaleMath(run.mathBox),
        measurementSource: run.measurementSource,
      );
  LayoutLine scaleLine(LayoutLine line) => LayoutLine(
        id: line.id,
        semanticNodeId: line.semanticNodeId,
        semanticNode: line.semanticNode,
        paragraphIndex: line.paragraphIndex,
        lineIndex: line.lineIndex,
        rect: scaleRect(line.rect),
        baseline: scaleOriginY + (line.baseline - scaleOriginY) * factor,
        ascent: line.ascent * factor,
        descent: line.descent * factor,
        leading: line.leading * factor,
        direction: line.direction,
        alignment: line.alignment,
        runs: List<LayoutRun>.unmodifiable(line.runs.map(scaleRun)),
        logicalRunIds: line.logicalRunIds,
        visualRunIds: line.visualRunIds,
        naturalWidth: line.naturalWidth * factor,
        resolvedWidth: line.resolvedWidth * factor,
        isJustified: line.isJustified,
        justificationOpportunityCount: line.justificationOpportunityCount,
        extraSpacePerOpportunity: line.extraSpacePerOpportunity * factor,
      );
  return LayoutBlock(
    id: block.id,
    semanticNodeId: block.semanticNodeId,
    semanticNode: block.semanticNode,
    kind: block.kind,
    rect: scaleRect(block.rect),
    lines: List<LayoutLine>.unmodifiable(block.lines.map(scaleLine)),
    children: List<LayoutBlock>.unmodifiable(
      block.children.map((child) => _scaleBlock(
        child,
        factor,
        originX: scaleOriginX,
        originY: scaleOriginY,
      )),
    ),
    decorations: List<LayoutDecoration>.unmodifiable(block.decorations.map((decoration) =>
        LayoutDecoration(
          id: decoration.id,
          semanticNodeId: decoration.semanticNodeId,
          kind: decoration.kind,
          rect: scaleRect(decoration.rect),
          strokeWidthPt: decoration.strokeWidthPt * factor,
          colorArgb: decoration.colorArgb,
          radiusPt: decoration.radiusPt * factor,
        ))),
    split: block.split,
    breakReason: block.breakReason,
    scaleFactor: block.scaleFactor * factor,
    keepTogether: block.keepTogether,
    continuation: block.continuation,
  );
}

LayoutLine _moveLine(LayoutLine line, double dx, double dy) =>
    LayoutLine(
      id: line.id,
      semanticNodeId: line.semanticNodeId,
      semanticNode: line.semanticNode,
      paragraphIndex: line.paragraphIndex,
      lineIndex: line.lineIndex,
      rect: line.rect.translate(dx, dy),
      baseline: line.baseline + dy,
      ascent: line.ascent,
      descent: line.descent,
      leading: line.leading,
      direction: line.direction,
      alignment: line.alignment,
      runs: List<LayoutRun>.unmodifiable(
        line.runs.map((run) => LayoutRun(
              id: run.id,
              semanticNodeId: run.semanticNodeId,
              semanticNode: run.semanticNode,
              contentKind: run.contentKind,
              semanticRole: run.semanticRole,
              text: run.text,
              x: run.x + dx,
              advance: run.advance,
              width: run.width,
              height: run.height,
              baselineOffset: run.baselineOffset,
              direction: run.direction,
              style: run.style,
              logicalIndex: run.logicalIndex,
              visualIndex: run.visualIndex,
              mathBox: run.mathBox,
              measurementSource: run.measurementSource,
            )),
      ),
      logicalRunIds: line.logicalRunIds,
      visualRunIds: line.visualRunIds,
      naturalWidth: line.naturalWidth,
      resolvedWidth: line.resolvedWidth,
      isJustified: line.isJustified,
      justificationOpportunityCount: line.justificationOpportunityCount,
      extraSpacePerOpportunity: line.extraSpacePerOpportunity,
    );
