import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selectable download storage presets (referencing mature apps like Pixes / Boorusama / Seal).
enum DownloadStoragePreset {
  /// Public Pictures album (`/storage/emulated/0/Pictures/SakuraView` on Android,
  /// `Downloads/SakuraView` on Desktop). Visible in system gallery apps.
  publicPictures,

  /// Public Downloads folder (`/storage/emulated/0/Download/SakuraView` on Android,
  /// `Downloads/SakuraView` on Desktop).
  publicDownloads,

  /// Public DCIM camera album (`/storage/emulated/0/DCIM/SakuraView` on Android).
  publicDcim,

  /// App-private isolated storage (`Android/data/vce1.sakuraview/files/Pictures/SakuraView`
  /// on Android, or `ApplicationDocumentsDirectory/SakuraView` on Desktop).
  /// Hidden from third-party gallery scanners.
  appPrivate,

  /// User-selected custom directory via folder picker.
  custom;

  String get title {
    switch (this) {
      case DownloadStoragePreset.publicPictures:
        return '系统相册 (Pictures)';
      case DownloadStoragePreset.publicDownloads:
        return '下载目录 (Download)';
      case DownloadStoragePreset.publicDcim:
        return '相机相册 (DCIM)';
      case DownloadStoragePreset.appPrivate:
        return '应用私有目录';
      case DownloadStoragePreset.custom:
        return '自定义目录';
    }
  }

  String get subtitle {
    switch (this) {
      case DownloadStoragePreset.publicPictures:
        return '系统图库可见';
      case DownloadStoragePreset.publicDownloads:
        return '公共下载文件夹';
      case DownloadStoragePreset.publicDcim:
        return 'DCIM 相册目录';
      case DownloadStoragePreset.appPrivate:
        return '仅应用内部访问';
      case DownloadStoragePreset.custom:
        return '指定本地存储路径';
    }
  }

  bool get isPublicStorage {
    switch (this) {
      case DownloadStoragePreset.publicPictures:
      case DownloadStoragePreset.publicDownloads:
      case DownloadStoragePreset.publicDcim:
        return true;
      case DownloadStoragePreset.appPrivate:
      case DownloadStoragePreset.custom:
        return false;
    }
  }

  static DownloadStoragePreset fromName(String? raw) {
    for (final v in DownloadStoragePreset.values) {
      if (v.name == raw) return v;
    }
    return DownloadStoragePreset.publicPictures;
  }
}

/// 首页及搜索页卡片尺寸档位。
enum GridSizePreset {
  large('大图'),
  standard('标准'),
  compact('紧凑');

  final String label;
  const GridSizePreset(this.label);

  static GridSizePreset fromName(String? raw) {
    for (final v in GridSizePreset.values) {
      if (v.name == raw) return v;
    }
    return GridSizePreset.standard;
  }

  /// 根据当前可视宽度与横竖屏方向计算网格列数。
  int calcColumns(double width, {required bool isLandscape}) {
    switch (this) {
      case GridSizePreset.large:
        return (width / 260.0).floor().clamp(1, 5);
      case GridSizePreset.standard:
        return (width / (isLandscape ? 172.0 : 180.0)).floor().clamp(2, 7);
      case GridSizePreset.compact:
        return (width / 136.0).floor().clamp(3, 8);
    }
  }
}

/// 首页底部悬浮导航栏显示策略。
enum FloatingNavMode {
  auto('自动显隐'),
  always('常驻显示'),
  hidden('永久隐藏');

  final String label;
  const FloatingNavMode(this.label);

  static FloatingNavMode fromName(String? raw) {
    for (final v in FloatingNavMode.values) {
      if (v.name == raw) return v;
    }
    return FloatingNavMode.auto;
  }
}

/// 下载默认画质偏好（默认下载原图，也可在设置中切换为中等清晰度大图）。
enum DownloadQuality {
  original('原图', '下载无压缩原始文件（默认）'),
  sample('中等尺寸', '下载压缩后的预览图');

  final String title;
  final String subtitle;

  const DownloadQuality(this.title, this.subtitle);

  static DownloadQuality fromName(String? raw) {
    for (final v in DownloadQuality.values) {
      if (v.name == raw) return v;
    }
    return DownloadQuality.original;
  }
}

class SettingsService {
  static final Logger _logger = Logger('SettingsService');
  static final Set<String> _verifiedWritableDirs = <String>{};
  static const String _downloadPathKey = 'download_path';
  static const String _downloadPresetKey = 'download_storage_preset';
  static const String _safeModeKey = 'safe_mode_enabled';
  static const String _downloadQualityKey = 'download_quality_preference';
  static const String _showGroupBadgeKey = 'show_group_badge';
  static const String _showR18BadgeKey = 'show_r18_badge';
  static const String _preloadImagesKey = 'preload_images_enabled';
  static const String _viewOriginalByDefaultKey = 'view_original_by_default';
  static const String _gridSizePresetKey = 'grid_size_preset';
  static const String _floatingNavModeKey = 'floating_nav_mode';

  Future<SharedPreferences> _getPrefs() async {
    return SharedPreferences.getInstance();
  }

  Future<bool> getShowGroupBadge() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_showGroupBadgeKey) ?? true;
  }

  Future<void> setShowGroupBadge(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_showGroupBadgeKey, enabled);
  }

  Future<bool> getShowR18Badge() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_showR18BadgeKey) ?? true;
  }

  Future<void> setShowR18Badge(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_showR18BadgeKey, enabled);
  }

  Future<bool> getPreloadImages() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_preloadImagesKey) ?? true;
  }

  Future<void> setPreloadImages(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_preloadImagesKey, enabled);
  }

  Future<bool> getViewOriginalByDefault() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_viewOriginalByDefaultKey) ?? false;
  }

  Future<void> setViewOriginalByDefault(bool enabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_viewOriginalByDefaultKey, enabled);
  }

  Future<GridSizePreset> getGridSizePreset() async {
    final prefs = await _getPrefs();
    return GridSizePreset.fromName(prefs.getString(_gridSizePresetKey));
  }

  Future<void> setGridSizePreset(GridSizePreset preset) async {
    final prefs = await _getPrefs();
    await prefs.setString(_gridSizePresetKey, preset.name);
  }

  Future<FloatingNavMode> getFloatingNavMode() async {
    final prefs = await _getPrefs();
    return FloatingNavMode.fromName(prefs.getString(_floatingNavModeKey));
  }

  Future<void> setFloatingNavMode(FloatingNavMode mode) async {
    final prefs = await _getPrefs();
    await prefs.setString(_floatingNavModeKey, mode.name);
  }

  Future<DownloadQuality> getDownloadQuality() async {
    final prefs = await _getPrefs();
    return DownloadQuality.fromName(prefs.getString(_downloadQualityKey));
  }

  Future<void> setDownloadQuality(DownloadQuality quality) async {
    final prefs = await _getPrefs();
    await prefs.setString(_downloadQualityKey, quality.name);
    _logger.info('Download quality set to: ${quality.name}');
  }

  Future<void> setSafeMode(bool isEnabled) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_safeModeKey, isEnabled);
    _logger.info('Safe mode state saved: $isEnabled');
  }

  Future<bool> getSafeMode() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_safeModeKey) ?? false;
  }

  Future<DownloadStoragePreset> getDownloadPreset() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_downloadPresetKey);
    if (raw != null) {
      return DownloadStoragePreset.fromName(raw);
    }
    // Check if user previously set a custom path
    final existingCustom = prefs.getString(_downloadPathKey);
    if (existingCustom != null && existingCustom.isNotEmpty) {
      if (existingCustom.contains('/Android/data/')) {
        return DownloadStoragePreset.appPrivate;
      }
      if (existingCustom.endsWith('/Pictures/SakuraView')) {
        return DownloadStoragePreset.publicPictures;
      }
      if (existingCustom.endsWith('/Download/SakuraView')) {
        return DownloadStoragePreset.publicDownloads;
      }
      if (existingCustom.endsWith('/DCIM/SakuraView')) {
        return DownloadStoragePreset.publicDcim;
      }
    }
    return DownloadStoragePreset.publicPictures;
  }

  Future<void> setDownloadPreset(
    DownloadStoragePreset preset, {
    String? customPath,
  }) async {
    final prefs = await _getPrefs();
    await prefs.setString(_downloadPresetKey, preset.name);
    final resolvedPath = await resolvePathForPreset(
      preset,
      customPath: customPath,
    );
    await prefs.setString(_downloadPathKey, resolvedPath);
    _logger.info(
      'Download preset set to ${preset.name} -> resolved path: $resolvedPath',
    );
  }

  Future<void> setDownloadPath(String path) async {
    final prefs = await _getPrefs();
    await prefs.setString(_downloadPathKey, path);
    _logger.info('Custom download path set to: $path');
  }

  Future<String?> getDownloadPath() async {
    final prefs = await _getPrefs();
    final stored = prefs.getString(_downloadPathKey);
    if (stored != null && stored.trim().isNotEmpty) {
      return stored.trim();
    }
    final preset = await getDownloadPreset();
    return resolvePathForPreset(preset);
  }

  /// Resolves the concrete filesystem directory for [preset].
  Future<String> resolvePathForPreset(
    DownloadStoragePreset preset, {
    String? customPath,
  }) async {
    if (preset == DownloadStoragePreset.custom &&
        customPath != null &&
        customPath.trim().isNotEmpty) {
      return _ensureDirectoryWithFallback(customPath.trim());
    }

    if (Platform.isAndroid) {
      const String androidRoot = '/storage/emulated/0';
      switch (preset) {
        case DownloadStoragePreset.publicPictures:
          return _ensureDirectoryWithFallback(
            p.join(androidRoot, 'Pictures', 'SakuraView'),
          );
        case DownloadStoragePreset.publicDownloads:
          return _ensureDirectoryWithFallback(
            p.join(androidRoot, 'Download', 'SakuraView'),
          );
        case DownloadStoragePreset.publicDcim:
          return _ensureDirectoryWithFallback(
            p.join(androidRoot, 'DCIM', 'SakuraView'),
          );
        case DownloadStoragePreset.appPrivate:
          final extDir =
              await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory();
          return _ensureDirectoryWithFallback(
            p.join(extDir.path, 'Pictures', 'SakuraView'),
          );
        case DownloadStoragePreset.custom:
          final prefs = await _getPrefs();
          final saved = prefs.getString(_downloadPathKey);
          if (saved != null && saved.trim().isNotEmpty) {
            return _ensureDirectoryWithFallback(saved.trim());
          }
          return _ensureDirectoryWithFallback(
            p.join(androidRoot, 'Pictures', 'SakuraView'),
          );
      }
    }

    if (Platform.isIOS) {
      switch (preset) {
        case DownloadStoragePreset.publicPictures:
        case DownloadStoragePreset.publicDownloads:
        case DownloadStoragePreset.publicDcim:
          final docDir = await getApplicationDocumentsDirectory();
          return _ensureDirectoryWithFallback(p.join(docDir.path, 'SakuraView'));
        case DownloadStoragePreset.appPrivate:
          final supportDir = await getApplicationSupportDirectory();
          return _ensureDirectoryWithFallback(
            p.join(supportDir.path, 'SakuraView_Private'),
          );
        case DownloadStoragePreset.custom:
          final prefs = await _getPrefs();
          final saved = prefs.getString(_downloadPathKey);
          if (saved != null && saved.trim().isNotEmpty) {
            return _ensureDirectoryWithFallback(saved.trim());
          }
          final docDir = await getApplicationDocumentsDirectory();
          return _ensureDirectoryWithFallback(p.join(docDir.path, 'SakuraView'));
      }
    }

    // Desktop (Windows / macOS / Linux)
    switch (preset) {
      case DownloadStoragePreset.publicPictures:
      case DownloadStoragePreset.publicDownloads:
      case DownloadStoragePreset.publicDcim:
        final dlDir =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        return _ensureDirectoryWithFallback(p.join(dlDir.path, 'SakuraView'));
      case DownloadStoragePreset.appPrivate:
        final docDir = await getApplicationDocumentsDirectory();
        return _ensureDirectoryWithFallback(
          p.join(docDir.path, 'SakuraView_Private'),
        );
      case DownloadStoragePreset.custom:
        final prefs = await _getPrefs();
        final saved = prefs.getString(_downloadPathKey);
        if (saved != null && saved.trim().isNotEmpty) {
          return _ensureDirectoryWithFallback(saved.trim());
        }
        final dlDir =
            await getDownloadsDirectory() ??
            await getApplicationDocumentsDirectory();
        return _ensureDirectoryWithFallback(p.join(dlDir.path, 'SakuraView'));
    }
  }

  /// Ensures [desiredPath] exists and supports real file creation, falling back to app storage if blocked.
  Future<String> ensureWritableDirectory(String desiredPath) {
    return _ensureDirectoryWithFallback(desiredPath);
  }

  /// Drops cached write-probe status so a directory will be re-checked after permission changes.
  static void invalidateWritableCache([String? path]) {
    if (path == null) {
      _verifiedWritableDirs.clear();
    } else {
      _verifiedWritableDirs.remove(path);
    }
  }

  Future<bool> _probeWritable(Directory dir) async {
    final probe = File(p.join(dir.path, '.sakuraview_probe.jpg'));
    try {
      await probe.writeAsBytes(const <int>[0], flush: true);
      if (await probe.exists()) {
        await probe.delete();
      }
      return true;
    } catch (_) {
      try {
        if (await probe.exists()) {
          await probe.delete();
        }
      } catch (_) {}
      return false;
    }
  }

  Future<String> _ensureDirectoryWithFallback(String desiredPath) async {
    try {
      final dir = Directory(desiredPath);
      if (_verifiedWritableDirs.contains(dir.path) && await dir.exists()) {
        return dir.path;
      }
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (await _probeWritable(dir)) {
        _verifiedWritableDirs.add(dir.path);
        return dir.path;
      }
      throw FileSystemException(
        'Directory exists but is not writable under storage sandbox',
        dir.path,
      );
    } catch (e) {
      _logger.warning(
        'Directory "$desiredPath" unavailable/not writable ($e), falling back to app private storage.',
      );
      final fallbackBase = Platform.isAndroid
          ? (await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory())
          : await getApplicationDocumentsDirectory();
      final fallbackDir = Directory(
        p.join(fallbackBase.path, 'Pictures', 'SakuraView'),
      );
      if (!await fallbackDir.exists()) {
        try {
          await fallbackDir.create(recursive: true);
        } catch (_) {}
      }
      _verifiedWritableDirs.add(fallbackDir.path);
      return fallbackDir.path;
    }
  }

  Future<String> getDefaultDownloadPath() async {
    return resolvePathForPreset(DownloadStoragePreset.publicPictures);
  }
}
