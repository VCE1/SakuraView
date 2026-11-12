import 'dart:io';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final Logger _logger = Logger('DownloadManager');
  final SettingsService _settingsService =
      SettingsService();
  Future<void> initDownloader() async {
    await FlutterDownloader.initialize(
      debug: true,
    );
    _logger.info('FlutterDownloader initialized.');
  }

  Future<bool> requestStoragePermission() async {
    return true;
  }

  Future<String?> getDownloadDirectory() async {
    final String? customPath = await _settingsService.getDownloadPath();
    if (customPath != null && customPath.isNotEmpty) {
      _logger.info('Detected custom download path: $customPath');
      final dir = Directory(customPath);
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (e) {
          _logger.severe('Failed to create custom directory: $customPath, error: $e');
        }
      }
      if (await dir.exists()) {
        _logger.info('Using custom download directory: $customPath');
        return customPath;
      }
    }

    _logger.info('No custom path set, using default download directory.');
    Directory? defaultDir;
    try {
      defaultDir = await getDownloadsDirectory();
    } catch (e) {
      _logger.warning('Failed to get downloads directory, trying fallback: $e');
    }
    if (Platform.isAndroid && defaultDir == null) {
      defaultDir = await getExternalStorageDirectory();
    }

    if (defaultDir == null) {
      _logger.severe('Unable to get any available download directory');
      return null;
    }
    final finalPath = '${defaultDir.path}/vce1.sakuraview';
    final finalDir = Directory(finalPath);
    if (!await finalDir.exists()) {
      try {
        await finalDir.create(recursive: true);
      } catch (e) {
        _logger.severe('Failed to create default download subdirectory: $finalPath, error: $e');
        return null;
      }
    }
    return finalPath;
  }

  Future<String?> enqueueDownload(
      String url, String fileName, Map<String, dynamic> postData) async {
    if (url.isEmpty || fileName.isEmpty) {
      _logger.warning('Download URL or filename is empty, cannot add to queue');
      return null;
    }

    if (!await requestStoragePermission()) {
      _logger.severe('No storage permission, cannot start download');
      throw Exception('No storage permission');
    }

    final String? savedDir = await getDownloadDirectory();
    if (savedDir == null) {
      _logger.severe('Unable to get download directory, cannot add to queue');
      throw Exception('Unable to get download directory');
    }
    try {
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: savedDir,
        fileName: fileName,
        showNotification: true,
        openFileFromNotification: true,
        saveInPublicStorage: true,
      );
      _logger.info('Download task added to queue: $taskId, URL: $url');
      return taskId;
    } catch (e) {
      _logger.severe('Failed to add download task to queue: $e');
      throw Exception('Failed to add download task: $e');
    }
  }

  Future<void> cancelDownload(String taskId) async {
    await FlutterDownloader.cancel(taskId: taskId);
    _logger.info('Download task cancelled: $taskId');
  }

  Future<String?> retryDownload(String taskId) async {
    final newTaskId = await FlutterDownloader.retry(taskId: taskId);
    _logger.info('Download task retried: $taskId -> $newTaskId');
    return newTaskId;
  }

  Future<void> pauseDownload(String taskId) async {
    await FlutterDownloader.pause(taskId: taskId);
    _logger.info('Download task paused: $taskId');
  }

  Future<String?> resumeDownload(String taskId) async {
    final newTaskId = await FlutterDownloader.resume(taskId: taskId);
    _logger.info('Download task resumed: $taskId -> $newTaskId');
    return newTaskId;
  }

  Future<void> removeTask(String taskId,
      {required bool shouldDeleteFile}) async {
    await FlutterDownloader.remove(
        taskId: taskId, shouldDeleteContent: shouldDeleteFile);
    _logger.info('Download task removed: $taskId, deleteFile: $shouldDeleteFile');
  }

  Future<List<DownloadTask>> loadTasks() async {
    return await FlutterDownloader.loadTasks() ?? [];
  }
}

