import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hive/hive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:vce1_sakuraview/api/zerochan_api_client.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';

class AndroidDownloadNotifier extends BaseDownloadNotifier {
  final Logger _logger = Logger('AndroidDownloadNotifier');
  final SettingsService _settingsService = SettingsService();

  static const MethodChannel _mediaScanChannel =
      MethodChannel('com.sakuraview.dev/media_scan');

  final List<AppDownloadTask> _allTasks = [];
  List<DownloadedItem> _downloadedItems = [];
  bool _isLoadingGallery = false;
  bool _isListenerInitialized = false;
  bool _isDisposed = false;

  final ReceivePort _port = ReceivePort();
  static final Completer<void> _downloaderInitializedCompleter =
      Completer<void>();

  @override
  bool get isLoadingGallery => _isLoadingGallery;

  @override
  List<DownloadedItem> get downloadedItems => _downloadedItems;

  @override
  List<AppDownloadTask> get downloadingTasks => _allTasks
      .where(
        (task) =>
            task.status == DownloadTaskStatus.enqueued ||
            task.status == DownloadTaskStatus.running ||
            task.status == DownloadTaskStatus.paused ||
            task.status == DownloadTaskStatus.failed,
      )
      .toList();

  AndroidDownloadNotifier() {
    _bindBackgroundIsolate();
    _downloaderInitializedCompleter.future.then((_) {
      _logger.info('FlutterDownloader initialized, loading tasks & gallery...');
      refreshTasks();
      scanForDownloadedImages();
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
      _port.sendPort,
      'downloader_send_port',
    );

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
          _logger.info('Download complete. File saved to: $fullPath');

          try {
            final postHiveModel = PostHiveModel.fromApiMap(task.postData);
            postHiveModel.localPath = fullPath;

            final postBox = Hive.box<PostHiveModel>('downloaded_posts');
            await postBox.put(postHiveModel.id, postHiveModel);
          } catch (e) {
            _logger.severe(
              'Failed to save metadata to Hive for post ID: ${task.postData['id']}. Error: $e',
            );
          }

          _allTasks.removeAt(taskIndex);
          notifyListeners();
          await _scanFile(fullPath);
        }
      }
    });
  }

  Future<void> _scanFile(String path) async {
    try {
      await _mediaScanChannel.invokeMethod('scanFile', {'path': path});
    } on PlatformException catch (e) {
      _logger.fine('Media scan skipped or failed: ${e.message}');
    } catch (_) {}
    if (!_isDisposed) {
      await scanForDownloadedImages();
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

    var url = postData['file_url'] as String? ?? '';
    if (url.isEmpty) return EnqueueResult.failed;

    if (url.contains('zerochan.net/600/')) {
      try {
        final detail = await ZerochanApiClient().getPostDetail(postId.toString());
        if (detail != null &&
            detail.fileUrl != null &&
            detail.fileUrl!.isNotEmpty) {
          url = detail.fileUrl!;
          postData['file_url'] = url;
          if (detail.fileExt != null && detail.fileExt!.isNotEmpty) {
            postData['file_ext'] = detail.fileExt;
          }
        }
      } catch (e) {
        _logger.fine('Zerochan detail fetch before download skipped: $e');
      }
    }

    final fileExt = postData['file_ext'] as String? ?? 'jpg';
    final fileName = '$postId.$fileExt';

    final String savePath = await _getDownloadPath();
    final targetFile = File(p.join(savePath, fileName));

    if (await targetFile.exists()) {
      final postBox = Hive.box<PostHiveModel>('downloaded_posts');
      final postInHive = postBox.get(postId);
      if (postInHive == null || postInHive.localPath != targetFile.path) {
        final postHiveModel = PostHiveModel.fromApiMap(postData);
        postHiveModel.localPath = targetFile.path;
        await postBox.put(postId, postHiveModel);
      }
      await scanForDownloadedImages();
      return EnqueueResult.alreadyDownloaded;
    }

    if (_allTasks.any((task) => task.postData['id'] == postId)) {
      return EnqueueResult.alreadyInQueue;
    }

    final saveDir = Directory(savePath);
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    final headers = resolveSiteImageHeaders(url);

    try {
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: savePath,
        fileName: fileName,
        headers: headers,
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
      _logger.severe('Failed to enqueue download: $e');
      return EnqueueResult.failed;
    }
  }

  @override
  Future<void> pauseDownload(AppDownloadTask task) async =>
      await FlutterDownloader.pause(taskId: task.taskId);

  @override
  Future<void> cancelDownload(AppDownloadTask task) async {
    await FlutterDownloader.cancel(taskId: task.taskId);
    _allTasks.removeWhere((t) => t.taskId == task.taskId);
    notifyListeners();
  }

  @override
  Future<void> removeTask(AppDownloadTask task) async {
    await FlutterDownloader.remove(
      taskId: task.taskId,
      shouldDeleteContent: true,
    );
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
    for (var task in List<AppDownloadTask>.from(downloadingTasks)) {
      await removeTask(task);
    }
  }

  @override
  Future<void> refreshTasks() async {
    await _downloaderInitializedCompleter.future;
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks == null) return;
    _allTasks.clear();
    final postBox = Hive.box<PostHiveModel>('downloaded_posts');
    for (var task in tasks) {
      if (task.status == DownloadTaskStatus.complete) continue;
      final idStr = task.filename?.split('.').first ?? '';
      final parsedId = int.tryParse(idStr);
      final cachedHive = parsedId != null ? postBox.get(parsedId) : null;
      _allTasks.add(
        AppDownloadTask.fromDownloaderTask(
          task,
          cachedHive?.toApiMap() ??
              {
                'id': parsedId ?? idStr,
                'preview_url': '',
                'author': '队列任务',
                'tags': task.filename ?? '',
              },
        ),
      );
    }
    if (!_isDisposed) notifyListeners();
  }

  @override
  void setupPhotoManagerListener() {
    if (_isListenerInitialized) return;
    _isListenerInitialized = true;
    scanForDownloadedImages();
  }

  @override
  Future<void> scanForDownloadedImages() async {
    if (_isDisposed) return;
    _isLoadingGallery = true;
    notifyListeners();

    try {
      final String activeDir = await _getDownloadPath();
      final postBox = Hive.box<PostHiveModel>('downloaded_posts');
      final Map<String, DownloadedItem> itemsByPath = {};

      // 1. Scan all records from Hive `downloaded_posts`
      for (final key in postBox.keys) {
        final post = postBox.get(key);
        if (post == null) continue;
        final ext = post.fileExt ?? 'jpg';
        final filename = '${post.id}.$ext';
        final candidatePaths = <String>{
          if (post.localPath != null && post.localPath!.isNotEmpty)
            post.localPath!,
          p.join(activeDir, filename),
        };

        for (final path in candidatePaths) {
          final file = File(path);
          if (await file.exists()) {
            final stat = await file.stat();
            itemsByPath[file.path] = DownloadedItem(
              id: post.id.toString(),
              filePath: file.path,
              filename: p.basename(file.path),
              creationDate: stat.modified,
              width: post.width ?? 0,
              height: post.height ?? 0,
              fileSizeBytes: stat.size,
              author: post.author,
              tags: post.tags,
            );
            break;
          }
        }
      }

      // 2. Also scan the active download directory directly for any image files
      final dir = Directory(activeDir);
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            final lower = entity.path.toLowerCase();
            if (lower.endsWith('.jpg') ||
                lower.endsWith('.jpeg') ||
                lower.endsWith('.png') ||
                lower.endsWith('.webp') ||
                lower.endsWith('.gif')) {
              if (!itemsByPath.containsKey(entity.path)) {
                final stat = await entity.stat();
                final base = p.basename(entity.path);
                final idPart = base.split('.').first;
                final postId = int.tryParse(idPart);
                final hivePost = postId != null ? postBox.get(postId) : null;
                itemsByPath[entity.path] = DownloadedItem(
                  id: idPart,
                  filePath: entity.path,
                  filename: base,
                  creationDate: stat.modified,
                  width: hivePost?.width ?? 0,
                  height: hivePost?.height ?? 0,
                  fileSizeBytes: stat.size,
                  author: hivePost?.author,
                  tags: hivePost?.tags,
                );
              }
            }
          }
        }
      }

      final sorted = itemsByPath.values.toList()
        ..sort((a, b) => b.creationDate.compareTo(a.creationDate));
      _downloadedItems = sorted;
    } catch (e, s) {
      _logger.severe('Error scanning downloaded images', e, s);
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
        }
      }

      if (item.filePath.isNotEmpty) {
        final file = File(item.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      _downloadedItems.removeWhere(
        (a) => a.filePath == item.filePath || a.id == item.id,
      );
      if (!_isDisposed) notifyListeners();
    } catch (e) {
      _logger.severe('Error deleting downloaded item: $e');
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
          _logger.warning('Failed to create custom dir $customPath: $e');
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
