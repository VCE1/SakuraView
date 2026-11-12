import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SettingsService {
  static final Logger _logger = Logger('SettingsService');
  static const String _downloadPathKey = 'download_path';
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

  Future<void> setDownloadPath(String path) async {
    final prefs = await _getPrefs();
    await prefs.setString(_downloadPathKey, path);
    _logger.info('Custom download path set to: $path');
  }

  Future<String?> getDownloadPath() async {
    final prefs = await _getPrefs();
    return prefs.getString(_downloadPathKey);
  }

  Future<String> getDefaultDownloadPath() async {
    Directory? storageDir;
    String finalPath;

    if (Platform.isAndroid) {
      storageDir = await getExternalStorageDirectory();
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      storageDir = await getDownloadsDirectory();
    } else {
      storageDir = await getApplicationDocumentsDirectory();
    }

    if (storageDir == null) {
      _logger.severe('Unable to get any available storage directory, using app private directory as fallback.');
      storageDir = await getApplicationDocumentsDirectory();
      finalPath = p.join(storageDir.path, 'vce1.sakuraviewDownloads');
    } else {
      if (Platform.isAndroid) {
        final picturesPath = p.join(storageDir.path, 'Pictures');
        final sakuraViewPath = p.join(picturesPath, 'vce1.sakuraview');
        finalPath = sakuraViewPath;
      } else {
        finalPath = p.join(storageDir.path, 'vce1.sakuraviewDownloads');
      }
    }

    final Directory targetDir = Directory(finalPath);
    if (!await targetDir.exists()) {
      try {
        await targetDir.create(recursive: true);
        _logger.info('Successfully created default download directory: $finalPath');
      } catch (e) {
        _logger.severe('Failed to create default download directory $finalPath: $e');
        finalPath = (await getApplicationDocumentsDirectory()).path;
        _logger.warning('Falling back to app documents directory: $finalPath');
      }
    }

    _logger.info('Default download path: $finalPath');
    return finalPath;
  }
}
