import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/core/theme/app_theme.dart';

enum ThemeVariant {
  system('跟随系统'),
  sakuraLight('浅色模式'),
  sakuraDark('深色模式'),
  pureBlack('OLED 纯黑');

  final String label;
  const ThemeVariant(this.label);

  bool get isDark => this == sakuraDark || this == pureBlack;
}

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'theme_variant';
  static const String _seedKey = 'theme_color_seed';
  static const String _pureBlackKey = 'theme_pure_black';

  ThemeVariant _variant = ThemeVariant.system;
  SakuraColorSeed _colorSeed = SakuraColorSeed.sakuraRose;
  bool _pureBlack = false;

  ThemeVariant get variant => _variant;
  SakuraColorSeed get colorSeed => _colorSeed;
  bool get pureBlack => _pureBlack || _variant == ThemeVariant.pureBlack;
  bool get isDarkMode => _variant.isDark;

  ThemeData get theme => AppTheme.buildLightTheme(_colorSeed);

  ThemeData get darkTheme => AppTheme.buildDarkTheme(
        seed: _colorSeed,
        pureBlack: pureBlack,
      );

  ThemeMode get themeMode {
    switch (_variant) {
      case ThemeVariant.sakuraLight:
        return ThemeMode.light;
      case ThemeVariant.sakuraDark:
      case ThemeVariant.pureBlack:
        return ThemeMode.dark;
      case ThemeVariant.system:
        return ThemeMode.system;
    }
  }

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key) ?? 'system';
    final seedName = prefs.getString(_seedKey) ?? SakuraColorSeed.sakuraRose.name;
    _pureBlack = prefs.getBool(_pureBlackKey) ?? false;
    _variant = _parse(value);
    if (_variant == ThemeVariant.pureBlack) {
      _pureBlack = true;
    }
    _colorSeed = SakuraColorSeed.values.firstWhere(
      (s) => s.name == seedName,
      orElse: () => SakuraColorSeed.sakuraRose,
    );
    notifyListeners();
  }

  Future<void> setVariant(ThemeVariant variant) async {
    _variant = variant;
    if (variant == ThemeVariant.pureBlack) {
      _pureBlack = true;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(variant));
    await prefs.setBool(_pureBlackKey, _pureBlack);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    switch (mode) {
      case ThemeMode.system:
        await setVariant(ThemeVariant.system);
        break;
      case ThemeMode.light:
        await setVariant(ThemeVariant.sakuraLight);
        break;
      case ThemeMode.dark:
        await setVariant(
            _pureBlack ? ThemeVariant.pureBlack : ThemeVariant.sakuraDark);
        break;
    }
  }

  Future<void> setPureBlack(bool enabled) async {
    _pureBlack = enabled;
    if (_variant == ThemeVariant.pureBlack && !enabled) {
      _variant = ThemeVariant.sakuraDark;
    } else if (_variant == ThemeVariant.sakuraDark && enabled) {
      _variant = ThemeVariant.pureBlack;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pureBlackKey, enabled);
    await prefs.setString(_key, _encode(_variant));
  }

  Future<void> setColorSeed(SakuraColorSeed seed) async {
    if (_colorSeed == seed) return;
    _colorSeed = seed;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seedKey, seed.name);
  }

  static ThemeVariant _parse(String value) {
    switch (value) {
      case 'sakuraDark':
        return ThemeVariant.sakuraDark;
      case 'pureBlack':
        return ThemeVariant.pureBlack;
      case 'sakuraLight':
        return ThemeVariant.sakuraLight;
      case 'system':
      default:
        return ThemeVariant.system;
    }
  }

  static String _encode(ThemeVariant variant) {
    switch (variant) {
      case ThemeVariant.sakuraLight:
        return 'sakuraLight';
      case ThemeVariant.sakuraDark:
        return 'sakuraDark';
      case ThemeVariant.pureBlack:
        return 'pureBlack';
      case ThemeVariant.system:
        return 'system';
    }
  }
}
