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
        return '公开相册目录 (Pictures/SakuraView)';
      case DownloadStoragePreset.publicDownloads:
        return '公开下载目录 (Download/SakuraView)';
      case DownloadStoragePreset.publicDcim:
        return '系统相机相册 (DCIM/SakuraView)';
      case DownloadStoragePreset.appPrivate:
        return '应用私有目录 (App Private Storage)';
      case DownloadStoragePreset.custom:
        return '自定义文件夹 (Custom Directory)';
    }
  }

  String get subtitle {
    switch (this) {
      case DownloadStoragePreset.publicPictures:
        return '保存在系统公开 Pictures 相册中，系统图库与其他应用可直接浏览';
      case DownloadStoragePreset.publicDownloads:
        return '保存在系统公开 Download 下载目录中，便于通过文件管理器统一管理';
      case DownloadStoragePreset.publicDcim:
        return '保存在系统 DCIM 相册目录中，兼容云相册自动备份';
      case DownloadStoragePreset.appPrivate:
        return '保存在应用沙盒私有目录中，不对外部相册暴露，卸载应用时随应用清理';
      case DownloadStoragePreset.custom:
        return '手动指定任意本地存储路径或外置存储文件夹';
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

class SettingsService {
  static final Logger _logger = Logger('SettingsService');
  static const String _downloadPathKey = 'download_path';
  static const String _downloadPresetKey = 'download_storage_preset';
  static const String _safeModeKey = 'safe_mode_enabled';

  Future<SharedPreferences> _getPrefs() async {
    return SharedPreferences.getInstance();
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

  Future<String> _ensureDirectoryWithFallback(String desiredPath) async {
    try {
      final dir = Directory(desiredPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    } catch (e) {
      _logger.warning(
        'Could not create directory "$desiredPath" ($e), falling back to app private storage.',
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
      return fallbackDir.path;
    }
  }

  Future<String> getDefaultDownloadPath() async {
    return resolvePathForPreset(DownloadStoragePreset.publicPictures);
  }
}
