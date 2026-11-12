// ignore: unused_element
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hive/hive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

class AndroidDownloadNotifier extends BaseDownloadNotifier {
  final Logger _logger = Logger('AndroidDownloadNotifier');
  final SettingsService _settingsService = SettingsService();

  static const MethodChannel _mediaScanChannel =
      MethodChannel('com.sakuraview.dev/media_scan');

  final List<AppDownloadTask> _allTasks = [];

  List<AssetEntity> _downloadedImages = [];
  bool _isLoadingGallery = false;
  bool _isPhotoManagerListenerInitialized = false;
  bool _isDisposed = false;

  final ReceivePort _port = ReceivePort();
  static final Completer<void> _downloaderInitializedCompleter =
      Completer<void>();

  @override
  bool get isLoadingGallery => _isLoadingGallery;

  @override
  List<DownloadedItem> get downloadedItems {
    return _downloadedImages.map((asset) {
      String filePathGuess = asset.relativePath ?? '';
      if (filePathGuess.isNotEmpty && asset.title != null) {
        filePathGuess += "/${asset.title}";
      }

      return DownloadedItem(
        id: asset.id,
        filePath: filePathGuess,
        filename: asset.title ?? 'unknown',
        creationDate: asset.createDateTime,
        width: asset.width,
        height: asset.height,
      );
    }).toList();
  }

  @override
  List<AppDownloadTask> get downloadingTasks => _allTasks
      .where((task) =>
          task.status == DownloadTaskStatus.enqueued ||
          task.status == DownloadTaskStatus.running ||
          task.status == DownloadTaskStatus.paused)
      .toList();

  AndroidDownloadNotifier() {
    _bindBackgroundIsolate();
    _downloaderInitializedCompleter.future.then((_) {
      _logger
          .info('FlutterDownloader is confirmed initialized, loading tasks...');
      refreshTasks();
    });
  }

  static void markDownloaderInitialized() {
    if (!_downloaderInitializedCompleter.isCompleted) {
      _downloaderInitializedCompleter.complete();
    }
  }

  void _bindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');

    _port.listen((dynamic data) async {
      if (_isDisposed) return;
      final String id = data[0] as String;
      final DownloadTaskStatus status =
          DownloadTaskStatus.fromInt(data[1] as int);
      final int progress = data[2] as int;

      final taskIndex = _allTasks.indexWhere((task) => task.taskId == id);
      if (taskIndex != -1) {
        final task = _allTasks[taskIndex];

        if (task.progress != progress || task.status != status) {
          task.status = status;
          task.progress = progress;
          notifyListeners();
        }

        if (status == DownloadTaskStatus.complete) {
          final String fullPath = p.join(task.savedDir, task.filename);
          _logger.info("Download complete. File saved to: $fullPath");

          try {
            final postHiveModel = PostHiveModel.fromApiMap(task.postData);
            postHiveModel.localPath = fullPath;

            final postBox = Hive.box<PostHiveModel>('downloaded_posts');
            await postBox.put(postHiveModel.id, postHiveModel);
            _logger.info(
                "Successfully saved/updated metadata and localPath in Hive for post ID: ${postHiveModel.id}");
          } catch (e) {
            _logger.severe(
                "Failed to save metadata to Hive for post ID: ${task.postData['id']}. Error: $e");
          }

          _scanFile(fullPath);
          _allTasks.removeAt(taskIndex);
          notifyListeners();
        }
      }
    });
  }

  Future<void> _scanFile(String path) async {
    try {
      await _mediaScanChannel.invokeMethod('scanFile', {'path': path});
      _logger.info("Successfully requested a media scan for: $path");
      await Future.delayed(const Duration(milliseconds: 2000));
      if (!_isDisposed) {
        scanForDownloadedImages();
      }
    } on PlatformException catch (e) {
      _logger.severe("Failed to trigger media scan: '${e.message}'.");
    }
  }

  void _updateTaskId(String oldId, String newId) {
    final taskIndex = _allTasks.indexWhere((t) => t.taskId == oldId);
    if (taskIndex != -1) {
      _allTasks[taskIndex].taskId = newId;
      notifyListeners();
    }
  }

  @override
  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData) async {
    await _downloaderInitializedCompleter.future;

    final postId = postData['id'] as int?;
    if (postId == null) return EnqueueResult.failed;

    final fileExt = postData['file_ext'] as String? ?? 'jpg';
    final fileName = "$postId.$fileExt";

    // 1. 鑾峰彇鐢ㄦ埛褰撳墠璁剧疆鐨勪笅杞借矾寰?
    final String savePath = await _getDownloadPath();
    final targetFile = File(p.join(savePath, fileName));

    // 2. 鏍稿績妫€鏌ワ細鍙叧蹇冩枃浠舵槸鍚﹀凡缁忓瓨鍦ㄤ簬鎴戜滑鏈熸湜鐨勬渶缁堣矾寰?
    if (await targetFile.exists()) {
      _logger.info(
          'File for post ID $postId already exists at the target location: ${targetFile.path}.');

      // 纭繚Hive涓殑璁板綍鏄渶鏂扮殑锛屽寘鍚纭殑璺緞
      final postBox = Hive.box<PostHiveModel>('downloaded_posts');
      final postInHive = postBox.get(postId);
      // 濡傛灉Hive涓病鏈夎褰曪紝鎴栬€呰褰曠殑璺緞涓嶆纭紝鍒欐洿鏂板畠
      if (postInHive == null || postInHive.localPath != targetFile.path) {
        final postHiveModel = PostHiveModel.fromApiMap(postData);
        postHiveModel.localPath = targetFile.path;
        await postBox.put(postId, postHiveModel);
        _logger
            .info('Updated Hive for post ID $postId with correct local path.');
      }
      return EnqueueResult.alreadyDownloaded;
    }

    // 3. 濡傛灉鏂囦欢鍦ㄦ柊璺緞涓嶅瓨鍦紝鍒欐棤璁哄浣曢兘搴旇寮€濮嬩笅杞?
    // 妫€鏌ユ槸鍚﹀凡鍦ㄤ笅杞介槦鍒椾腑锛堥伩鍏嶉噸澶嶆坊鍔犱换鍔★級
    if (_allTasks.any((task) => task.postData['id'] == postId)) {
      return EnqueueResult.alreadyInQueue;
    }

    final url = postData['file_url'] as String? ?? '';
    if (url.isEmpty) return EnqueueResult.failed;

    final saveDir = Directory(savePath);
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    try {
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: savePath,
        fileName: fileName,
        showNotification: true,
        openFileFromNotification: true,
        saveInPublicStorage: false,
      );

      if (taskId != null) {
        final newTask = AppDownloadTask(
          taskId: taskId,
          filename: fileName,
          url: url,
          status: DownloadTaskStatus.enqueued,
          progress: 0,
          postData: postData,
          savedDir: savePath,
        );
        _allTasks.add(newTask);
        notifyListeners();
        return EnqueueResult.success;
      }
      return EnqueueResult.failed;
    } catch (e) {
      _logger.severe("Failed to enqueue download: $e");
      return EnqueueResult.failed;
    }
  }

  // ... 鐪佺暐鍏朵粬涓嶅彉鐨勬柟娉?...

  @override
  Future<void> pauseDownload(AppDownloadTask task) async =>
      await FlutterDownloader.pause(taskId: task.taskId);
  @override
  Future<void> cancelDownload(AppDownloadTask task) async =>
      await FlutterDownloader.cancel(taskId: task.taskId);
  @override
  Future<void> removeTask(AppDownloadTask task) async {
    await FlutterDownloader.remove(
        taskId: task.taskId, shouldDeleteContent: true);
    _allTasks.removeWhere((t) => t.taskId == task.taskId);
    notifyListeners();
  }

  @override
  Future<void> resumeDownload(AppDownloadTask task) async {
    final newTaskId = await FlutterDownloader.resume(taskId: task.taskId);
    if (newTaskId != null) _updateTaskId(task.taskId, newTaskId);
  }

  @override
  Future<void> retryDownload(AppDownloadTask task) async {
    final newTaskId = await FlutterDownloader.retry(taskId: task.taskId);
    if (newTaskId != null) _updateTaskId(task.taskId, newTaskId);
  }

  @override
  Future<void> pauseAllDownloads() async {
    for (var task in downloadingTasks) {
      if (task.status == DownloadTaskStatus.running) {
        await pauseDownload(task);
      }
    }
  }

  @override
  Future<void> cancelAllDownloads() async {
    for (var task in downloadingTasks) {
      await cancelDownload(task);
    }
  }

  @override
  Future<void> refreshTasks() async {
    await _downloaderInitializedCompleter.future;
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks == null) return;
    _allTasks.clear();
    for (var task in tasks) {
      _allTasks.add(AppDownloadTask.fromDownloaderTask(task, {
        'id': task.filename?.split('.').first,
        'preview_url': '',
        'author': '宸插瓨鍦ㄧ殑浠诲姟',
        'tags': task.filename,
      }));
    }
    notifyListeners();
  }

  @override
  void setupPhotoManagerListener() {
    if (_isPhotoManagerListenerInitialized) return;
    PhotoManager.addChangeCallback((details) {
      _logger.info("Photo gallery changed, refreshing...");
      scanForDownloadedImages();
    });
    scanForDownloadedImages();
    _isPhotoManagerListenerInitialized = true;
  }

  @override
  Future<void> scanForDownloadedImages() async {
    if (_isDisposed) return;
    _isLoadingGallery = true;
    notifyListeners();
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      _logger.warning('Photo library permission denied');
      _isLoadingGallery = false;
      if (!_isDisposed) notifyListeners();
      return;
    }
    try {
      final String? customDownloadPath =
          await _settingsService.getDownloadPath();

      List<AssetPathEntity> albums =
          await PhotoManager.getAssetPathList(type: RequestType.image);
      List<AssetEntity> allAssets = [];

      if (customDownloadPath != null && customDownloadPath.isNotEmpty) {
        _logger.info('Scanning custom download path: $customDownloadPath');
        for (final album in albums) {
          final assetsInAlbum = await album.getAssetListRange(
              start: 0, end: await album.assetCountAsync);
          for (final asset in assetsInAlbum) {
            final file = await asset.originFile;
            if (file != null && file.path.startsWith(customDownloadPath)) {
              allAssets.add(asset);
            }
          }
        }
      } else {
        final defaultPath = await _settingsService.getDefaultDownloadPath();
        final defaultAlbumName =
            p.basename(p.dirname(defaultPath)); // e.g., Pictures
        final appAlbumName = p.basename(defaultPath); // e.g., vce1.sakuraview

        for (final album in albums) {
          if (album.name.toLowerCase() == appAlbumName.toLowerCase() ||
              album.name.toLowerCase() == defaultAlbumName.toLowerCase()) {
            _logger.info("Scanning potential album: ${album.name}");
            final assetsInAlbum = await album.getAssetListRange(
                start: 0, end: await album.assetCountAsync);
            allAssets.addAll(assetsInAlbum.where((asset) =>
                asset.relativePath?.contains(appAlbumName) ?? false));
          }
        }
      }

      _downloadedImages = allAssets.toSet().toList();
      _downloadedImages
          .sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    } catch (e, s) {
      _logger.severe("鎵弿鐩稿唽鏃跺嚭閿?", e, s);
      _downloadedImages = [];
    } finally {
      _isLoadingGallery = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  @override
  Future<void> deleteDownloadedItem(DownloadedItem item) async {
    try {
      final postIdString = item.filename.split('.').first;
      final postId = int.tryParse(postIdString);

      if (postId != null) {
        final postBox = Hive.box<PostHiveModel>('downloaded_posts');
        if (postBox.containsKey(postId)) {
          await postBox.delete(postId);
          _logger.info("Deleted metadata from Hive for post ID: $postId");
        }
      }

      final List<String> result =
          await PhotoManager.editor.deleteWithIds([item.id]);

      if (result.isNotEmpty) {
        _downloadedImages.removeWhere((a) => a.id == item.id);
        notifyListeners();
        _logger.info("Successfully deleted file with assetId: ${item.id}");
      }
    } catch (e) {
      _logger.severe("鍒犻櫎鍥剧墖鏃跺嚭閿? $e");
    }
  }

  Future<String> _getDownloadPath() async {
    final String? customPath = await _settingsService.getDownloadPath();
    if (customPath != null && customPath.isNotEmpty) {
      final dir = Directory(customPath);
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (e) {
          _logger.severe('鍒涘缓鐢ㄦ埛鑷畾涔夌洰褰曞け璐? $customPath, 閿欒: $e');
        }
      }
      if (await dir.exists()) {
        return customPath;
      }
    }
    return await _settingsService.getDefaultDownloadPath();
  }

  @override
  void dispose() {
    _isDisposed = true;
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close();
    super.dispose();
  }
}

