import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:writing_questions_app/layout/canonical/flutter_text_metrics.dart';
import 'package:writing_questions_app/models/paper_font.dart';

/// Widget tests intentionally default to Ahem. Register the *existing* app and
/// package fonts from Flutter's generated production manifest, not substitute
/// fonts. Missing math assets must fail rather than yield black-block evidence.
Future<void> loadProductionEvidenceFonts() async {
  await FlutterTextMetrics.ensureFontsLoaded();
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  final loaded = <Map<String, Object>>[];
  final paperFamilies = PaperFont.values.map((font) => font.family).toSet();
  for (final value in manifest) {
    final entry = value as Map<String, dynamic>;
    final family = entry['family'] as String;
    if (paperFamilies.contains(family)) continue;
    final loader = FontLoader(family);
    final assets = <Map<String, Object>>[];
    for (final value in entry['fonts'] as List<dynamic>) {
      final font = value as Map<String, dynamic>;
      final asset = font['asset'] as String;
      final bytes = await rootBundle.load(asset);
      if (bytes.lengthInBytes == 0) throw StateError('Empty production font: $asset');
      loader.addFont(Future.value(bytes));
      assets.add(<String, Object>{'asset': asset, 'bytes': bytes.lengthInBytes});
    }
    await loader.load();
    loaded.add(<String, Object>{'family': family, 'assets': assets});
  }
  for (final name in <String>['KaTeX_Main', 'KaTeX_Math']) {
    if (!loaded.any((entry) => (entry['family']! as String).endsWith('/$name'))) {
      throw StateError('Production math family missing from FontManifest: $name');
    }
  }
  Directory('build/production_fragment_repro').createSync(recursive: true);
  File('build/production_fragment_repro/production-font-assets.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object>{
      'source': 'Flutter generated FontManifest.json; unchanged production assets',
      'families': loaded,
    }));
}
