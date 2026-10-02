import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart' show MathStyle;

import '../../services/math_snapshot_renderer.dart';
import 'safe_math_tex.dart';

/// مضيف خفيّ يرسم المعادلات خارج الشاشة بمحرك العرض نفسه ثم يعيدها لقطات.
///
/// يُلَفّ حوله التطبيق كلُّه (`MaterialApp.builder` في `lib/main.dart`)، فهو
/// متاح لكل مسارات التصدير دون أن يمرّر أي شاشة شيئاً، وبلا أثر بصري:
/// شجرة اللقطات تُوضع خارج حدود اللوحة (`left` سالب كبير) فلا تُرى، لكنها
/// تخطيطاً ورسمها يجريان فعلاً فيأخذهما `RenderRepaintBoundary.toImageSync`
/// — الالتقاط متزامن بلا انتظار حلقة أحداث، والقياسان (البكسل والنقاط) يأتيان
/// من المحرك نفسه: بكسلات الصورة = القياس بالنقاط × الكثافة.
///
/// لماذا مضيف لا رسم مباشر؟ لأن المحرك الذي نريد أن نطابقه **ودجت**: تخطيط
/// `flutter_math_fork` يعيش في RenderObjects (لا واجهة قياس عامة عنده)،
/// فأي نتيجة مطابقة تستلزم بناء الودجت نفسه. وهذا الملف يبنيه بالضبط كما
/// تبنيه اللوحة: [SafeMathTex] — بكل ارتداداته الآمنة نفسها.
class MathSnapshotHost extends StatefulWidget {
  const MathSnapshotHost({super.key, this.child});

  final Widget? child;

  @override
  State<MathSnapshotHost> createState() => _MathSnapshotHostState();
}

class _MathSnapshotHostState extends State<MathSnapshotHost> {
  /// موضع الشجرة خارج اللوحة: أبعد من أي كثافة شاشة معقولة.
  static const double _offscreen = -10000;

  /// محاولات انتظار اكتمال التخطيط/الرسم قبل إعلان التعذّر.
  static const int _maxAttempts = 32;

  final List<_SnapshotJob> _jobs = <_SnapshotJob>[];
  bool _pumpScheduled = false;

  /// مرجع ثابت للتسجيل والإلغاء: `this._render` tear-off جديد في كل مرة،
  /// فلو استُعمل مباشرةً لفشل `identical` في `detach` وبقي المضيف الميت
  /// مسجَّلاً (ولكانت اللقطات بعده تُسلَّم إلى حالة غير مُركَّبة).
  late final MathSnapshotProvider _registeredProvider = _render;

  @override
  void initState() {
    super.initState();
    MathSnapshotRenderer.debugLastFailure = null;
    MathSnapshotRenderer.attach(_registeredProvider);
  }

  @override
  void dispose() {
    // كل مهمة لم تُلتقط بعد تُرَدّ بـ null فوراً: لا تُعلَّق ورقة تنتظر مصدراً
    // مات (الإطار التالي لن يأتي لهذا الودجت أبداً).
    for (final job in List<_SnapshotJob>.of(_jobs)) {
      job.complete(null);
    }
    _jobs.clear();
    MathSnapshotRenderer.detach(_registeredProvider);
    super.dispose();
  }

  Future<MathSnapshot?> _render(
    String latex,
    double fontSizePt,
    double density,
  ) {
    if (!mounted) {
      return Future<MathSnapshot?>.value();
    }
    final job = _SnapshotJob(
      latex: latex,
      fontSizePt: fontSizePt,
      density: density,
    );
    setState(() => _jobs.add(job));
    _schedulePump();
    return job.completer.future;
  }

  void _schedulePump() {
    if (_pumpScheduled) {
      return;
    }
    _pumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pumpScheduled = false;
      if (mounted) {
        _pump();
      }
    });
    // إطار مضمون: بلا هذا لا يأتي إطارٌ جديد إن لم يكن شيء يطلبه — فأي
    // ارتداد بعد تعذّر الرسم كان يعلّق بلا محاولة تالية.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _pump() {
    for (final job in List<_SnapshotJob>.of(_jobs)) {
      final boundary = _boundaryOf(job);
      if (boundary == null) {
        _retryOrFail(job);
        continue;
      }
      final MathSnapshot snapshot;
      try {
        // اللقطة متزامنة كلها (toImageSync): تُؤخذ عقب paint مباشرةً، بلا
        // انتظار حلقة أحداث — ولا ترميز PNG هنا: المُهلِك يُرمَّز عند
        // المستهلك (وثيق `MathSnapshot`)، فبقى الملتقِط خطوة واحدة لا تُعلَّق.
        snapshot = _capture(job, boundary, boundary.toImageSync());
      } catch (error) {
        _report('toImageSync: $error');
        _retryOrFail(job);
        continue;
      }
      MathSnapshotRenderer.debugLastFailure = null;
      if (!job.completer.isCompleted) {
        job.complete(snapshot);
      }
      if (mounted) {
        setState(() => _jobs.remove(job));
      }
    }
  }

  RenderRepaintBoundary? _boundaryOf(_SnapshotJob job) {
    final context = job.key.currentContext;
    if (context == null) {
      _report('ودجت اللقطة غير مُركَّبة بعد');
      return null;
    }
    final object = context.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      _report('ليس RenderRepaintBoundary (${object.runtimeType})');
      return null;
    }
    if (!object.hasSize) {
      _report('بلا قياس بعد');
      return null;
    }
    if (object.size.isEmpty) {
      _report('قياس فارغ ${object.size}');
      return null;
    }
    return object;
  }

  /// سبب آخر تعذّر — للتشخيص فقط (الاختبارات تطبعه)، لا يُبنى عليه منطق.
  static void _report(String reason) {
    MathSnapshotRenderer.debugLastFailure = reason;
  }

  void _retryOrFail(_SnapshotJob job) {
    job.attempts++;
    if (job.attempts >= _maxAttempts) {
      _report('تعذّر بعد ${job.attempts} محاولة');
      job.complete(null);
      if (mounted) {
        setState(() => _jobs.remove(job));
      }
      return;
    }
    _schedulePump();
  }

  MathSnapshot _capture(
    _SnapshotJob job,
    RenderRepaintBoundary boundary,
    ui.Image image,
  ) {
    // لا scale ولا pixelRatio: الدقة تأتي من رسم الودجت بخط
    // `fontSizePt × density` ثم قسمة قياسه على الكثافة — بؤرة الرسم بكسل
    // منطقي لكل نقطة، فتُعطي الكثافة نفسها بلا اعتماد على أي إصدار من
    // Flutter (وتخطيط الخطوط متجانس القياس: لا فرق في المواضع).
    return MathSnapshot(
      image: image,
      widthPt: boundary.size.width / job.density,
      heightPt: boundary.size.height / job.density,
      baselinePt: _baselineOf(boundary, job.density),
    );
  }

  /// خط الأساس من المحرك نفسه إن أعلنه (بمقياس النقاط)؛ لا تقدير بديل عند
  /// غيابه — عندها يُستعمل الارتفاع كله، فتجلس الصورة على السطر بلا نزول.
  double? _baselineOf(RenderRepaintBoundary boundary, double density) {
    // الصندوق الوسيط قد لا يجيب فيُسأل ابنه المباشر؛ ومن لا يعلن عن خط أساسه
    // يُترك null (لا تخمين: تُستعمل الصورة بارتفاعها كاملاً).
    for (final RenderBox? box in <RenderBox?>[boundary, boundary.child]) {
      if (box == null) {
        continue;
      }
      try {
        final baseline = box.getDistanceToBaseline(TextBaseline.alphabetic);
        if (baseline != null) {
          return baseline / density;
        }
      } catch (_) {
        // المحرك لا يدعم السؤال عند هذا العقد: ننتقل إلى من يليه.
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        if (widget.child != null) Positioned.fill(child: widget.child!),
        if (_jobs.isNotEmpty)
          Positioned(
            left: _offscreen,
            top: 0,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: MediaQuery(
                  // صندوق مقياس ثابت: لا يتأثر التكبير ولا بدوران الجهاز.
                  data: const MediaQueryData(size: Size(6000, 6000)),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final job in _jobs)
                          RepaintBoundary(key: job.key, child: _build(job)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// نفس ما تبنيه المعاينة، بخط مضروب في الكثافة: القياس يُقرأ مقسوماً
  /// عليها، فتبقى الأبعاد بالنقاط والشكل شكلاً حرفياً من المحرك نفسه.
  Widget _build(_SnapshotJob job) {
    return UnconstrainedBox(
      alignment: AlignmentDirectional.topStart,
      child: SafeMathTex(
        job.latex,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(
          fontSize: job.fontSizePt * job.density,
          color: const Color(0xFF000000),
        ),
      ),
    );
  }
}

/// طلب لقطة واحدة: مفتاح للوصول إلى الودجت، و`Completer` لإرجاع النتيجة.
class _SnapshotJob {
  _SnapshotJob({
    required this.latex,
    required this.fontSizePt,
    required this.density,
  });

  final String latex;
  final double fontSizePt;
  final double density;
  final GlobalKey key = GlobalKey(debugLabel: 'math-snapshot');
  final Completer<MathSnapshot?> completer = Completer<MathSnapshot?>();
  int attempts = 0;

  void complete(MathSnapshot? snapshot) {
    if (!completer.isCompleted) {
      completer.complete(snapshot);
    }
  }
}
