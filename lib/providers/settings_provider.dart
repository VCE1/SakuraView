import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

/// 响应式应用浏览与交互设置状态。
class SettingsProvider extends ChangeNotifier {
  final SettingsService _service;

  bool _showGroupBadge = true;
  bool _showR18Badge = true;
  bool _preloadImages = true;
  bool _viewOriginalByDefault = false;
  GridSizePreset _gridSizePreset = GridSizePreset.standard;
  FloatingNavMode _floatingNavMode = FloatingNavMode.auto;
  bool _loaded = false;

  SettingsProvider({SettingsService? service})
      : _service = service ?? SettingsService() {
    load();
  }

  bool get showGroupBadge => _showGroupBadge;
  bool get showR18Badge => _showR18Badge;
  bool get preloadImages => _preloadImages;
  bool get viewOriginalByDefault => _viewOriginalByDefault;
  GridSizePreset get gridSizePreset => _gridSizePreset;
  FloatingNavMode get floatingNavMode => _floatingNavMode;
  bool get isLoaded => _loaded;

  /// 安全查找当前上下文中的 [SettingsProvider]，在隔离组件测试中未注入时返回 `null`。
  static SettingsProvider? maybeOf(
    BuildContext context, {
    bool listen = true,
  }) {
    try {
      return Provider.of<SettingsProvider>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> load() async {
    try {
      final results = await Future.wait<dynamic>([
        _service.getShowGroupBadge(),
        _service.getShowR18Badge(),
        _service.getPreloadImages(),
        _service.getViewOriginalByDefault(),
        _service.getGridSizePreset(),
        _service.getFloatingNavMode(),
      ]);
      _showGroupBadge = results[0] as bool;
      _showR18Badge = results[1] as bool;
      _preloadImages = results[2] as bool;
      _viewOriginalByDefault = results[3] as bool;
      _gridSizePreset = results[4] as GridSizePreset;
      _floatingNavMode = results[5] as FloatingNavMode;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      _loaded = true;
    }
  }

  Future<void> setShowGroupBadge(bool enabled) async {
    if (_showGroupBadge == enabled) return;
    _showGroupBadge = enabled;
    notifyListeners();
    await _service.setShowGroupBadge(enabled);
  }

  Future<void> setShowR18Badge(bool enabled) async {
    if (_showR18Badge == enabled) return;
    _showR18Badge = enabled;
    notifyListeners();
    await _service.setShowR18Badge(enabled);
  }

  Future<void> setPreloadImages(bool enabled) async {
    if (_preloadImages == enabled) return;
    _preloadImages = enabled;
    notifyListeners();
    await _service.setPreloadImages(enabled);
  }

  Future<void> setViewOriginalByDefault(bool enabled) async {
    if (_viewOriginalByDefault == enabled) return;
    _viewOriginalByDefault = enabled;
    notifyListeners();
    await _service.setViewOriginalByDefault(enabled);
  }

  Future<void> setGridSizePreset(GridSizePreset preset) async {
    if (_gridSizePreset == preset) return;
    _gridSizePreset = preset;
    notifyListeners();
    await _service.setGridSizePreset(preset);
  }

  Future<void> setFloatingNavMode(FloatingNavMode mode) async {
    if (_floatingNavMode == mode) return;
    _floatingNavMode = mode;
    notifyListeners();
    await _service.setFloatingNavMode(mode);
  }
}
