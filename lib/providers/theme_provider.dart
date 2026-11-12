import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/core/theme/app_theme.dart';

enum ThemeVariant {
  sakuraLight('Sakura Light'),
  sakuraDark('Sakura Dark'),
  pureBlack('Pure Black'),
  system('Follow System');

  final String label;
  const ThemeVariant(this.label);

  bool get isDark => this == sakuraDark || this == pureBlack;
}

class ThemeProvider extends ChangeNotifier {
  static const String _key = 'theme_variant';

  ThemeVariant _variant = ThemeVariant.sakuraLight;

  ThemeVariant get variant => _variant;
  bool get isDarkMode => _variant.isDark;

  ThemeData get theme {
    switch (_variant) {
      case ThemeVariant.sakuraLight:
        return AppTheme.lightTheme;
      case ThemeVariant.sakuraDark:
        return AppTheme.darkTheme;
      case ThemeVariant.pureBlack:
        return AppTheme.pureBlackTheme;
      case ThemeVariant.system:
        return AppTheme.lightTheme;
    }
  }

  ThemeData get darkTheme {
    switch (_variant) {
      case ThemeVariant.pureBlack:
        return AppTheme.pureBlackTheme;
      case ThemeVariant.sakuraDark:
        return AppTheme.darkTheme;
      case ThemeVariant.sakuraLight:
        return AppTheme.darkTheme;
      case ThemeVariant.system:
        return AppTheme.darkTheme;
    }
  }

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
    final value = prefs.getString(_key) ?? 'sakuraLight';
    _variant = _parse(value);
    notifyListeners();
  }

  Future<void> setVariant(ThemeVariant variant) async {
    if (_variant == variant) return;
    _variant = variant;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode(variant));
  }

  static ThemeVariant _parse(String value) {
    switch (value) {
      case 'sakuraDark':
        return ThemeVariant.sakuraDark;
      case 'pureBlack':
        return ThemeVariant.pureBlack;
      case 'system':
        return ThemeVariant.system;
      default:
        return ThemeVariant.sakuraLight;
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
