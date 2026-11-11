import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File _resolveSource(String relativePath) {
  final direct = File(relativePath);
  if (direct.existsSync()) {
    return direct;
  }
  final inPlugin = File('plugins/tray/$relativePath');
  if (inPlugin.existsSync()) {
    return inPlugin;
  }
  return direct;
}

void main() {
  late String menuSource;

  setUpAll(() {
    menuSource = _resolveSource(
      'macos/tray/Sources/tray/TrayMenuItemView.swift',
    ).readAsStringSync();
  });

  test('menu flags are drawn with the bundled Twemoji font', () {
    expect(
      menuSource,
      contains(
        'App.framework/Resources/flutter_assets/assets/fonts/Twemoji.Mozilla.ttf',
      ),
    );
    expect(menuSource, contains('CTFontManagerRegisterFontsForURL'));
    expect(menuSource, contains('TwemojiCOLRv0-Regular'));
    expect(menuSource, contains('(0x1F1E6...0x1F1FF)'));
  });

  test('a flag pair stays in one run so the ligature can form', () {
    expect(menuSource, contains('String(scalars[index..<end])'));
    expect(menuSource, contains('scalars.index(after: next)'));
  });

  test('the row measures the label with the same flag string it draws', () {
    expect(menuSource, contains('labelWidth(content.label)'));
    expect(menuSource, contains('drawLabel(content.label'));
    expect(
      menuSource,
      contains('ceil(label(text, color: .labelColor).size().width)'),
    );
  });
}
