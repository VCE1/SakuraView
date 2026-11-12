import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:vce1_sakuraview/api/zerochan_api_client.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

class WindowsDownloadNotifier extends BaseDownloadNotifier {
  final Logger _logger = Logger('WindowsDownloadNotifier');
  final Dio _dio = Dio(
    BaseOptions(
      headers: {
        'User-Agent': 'vce1.sakuraview/1.1 (vce1)',
      },
    ),
  );
  final List<AppDownloadTask> _tasks = [];
  List<DownloadedItem> _downloadedItems = [];
  late Box<PostHiveModel> _postBox;
  final SettingsService _settingsService = SettingsService();
  bool _isDisposed = false;

  final Map<String, CancelToken> _cancelTokens = {};

  @override
  bool get isLoadingGallery => false;

  @override
  List<AppDownloadTask> get downloadingTasks => _tasks.toList();

  @override
  List<DownloadedItem> get downloadedItems => _downloadedItems;

  WindowsDownloadNotifier() {
    _postBox = Hive.box<PostHiveModel>('downloaded_posts');
    scanForDownloadedImages();
  }

  @override
  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData) async {
    var url = postData['file_url'] as String? ?? '';
    if (url.isEmpty) return EnqueueResult.failed;

    if (url.contains('zerochan.net/600/') && postData['id'] != null) {
      try {
        final detail = await ZerochanApiClient()
            .getPostDetail(postData['id'].toString());
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

    if (_tasks.any((task) => task.postData['id'] == postData['id'])) {
      return EnqueueResult.alreadyInQueue;
    }

    if (_postBox.containsKey(postData['id'])) {
      return EnqueueResult.alreadyDownloaded;
    }

    final downloadsPath = await _getDownloadPath();
    final fileExt = postData['file_ext'] as String? ?? 'jpg';
    final fileName = "${postData['id']}.$fileExt";
    final savePath = p.join(downloadsPath, fileName);

    if (await File(savePath).exists()) {
      if (!_postBox.containsKey(postData['id'])) {
        final postHiveModel = PostHiveModel.fromApiMap(postData);
        await _postBox.put(postHiveModel.id, postHiveModel);
        _logger.info(
            'Found existing file for ID: ${postData['id']}, updated Hive.');
      }
      return EnqueueResult.alreadyDownloaded;
    }

    final task = AppDownloadTask(
      taskId: postData['id'].toString(),
      filename: fileName,
      url: url,
      status: 'Pending',
      progress: 0,
      postData: postData,
      savedDir: downloadsPath,
    );
    _tasks.add(task);
    notifyListeners();
    _startDownload(task, savePath);
    return EnqueueResult.success;
  }

  void _startDownload(AppDownloadTask task, String savePath) async {
    final cancelToken = CancelToken();
    _cancelTokens[task.taskId] = cancelToken;
    int lastNotifiedProgress = -1;

    try {
      task.status = 'Downloading';
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());

      await _dio.download(
        task.url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final int currentProgress = (received / total * 100).toInt();
            if (currentProgress > lastNotifiedProgress) {
              task.progress = currentProgress;
              lastNotifiedProgress = currentProgress;
              Future.microtask(() {
                if (!_isDisposed) notifyListeners();
              });
            }
          }
        },
      );
      task.status = 'Completed';
      task.progress = 100;
      _logger.info('Windows download complete: ${task.filename}');

      final postHiveModel = PostHiveModel.fromApiMap(task.postData);
      await _postBox.put(postHiveModel.id, postHiveModel);
      _logger.info('Saved post data to Hive for ID: ${postHiveModel.id}');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        task.status = 'Cancelled';
        _logger.info('Windows download cancelled: ${task.filename}');
      } else {
        task.status = 'Failed';
        _logger.severe('Windows download failed: $e');
      }
    } catch (e) {
      task.status = 'Failed';
      _logger.severe('Windows download failed with unknown error: $e');
    } finally {
      _tasks.removeWhere((t) => t.taskId == task.taskId);
      _cancelTokens.remove(task.taskId);

      Future.microtask(() async {
        if (!_isDisposed) {
          notifyListeners();
          await Future.delayed(const Duration(milliseconds: 1200));
          await scanForDownloadedImages();
        }
      });
    }
  }

  @override
  Future<void> scanForDownloadedImages() async {
    final downloadsPath = await _getDownloadPath();
    final List<DownloadedItem> freshList = [];

    final allPostIds = _postBox.keys.toList();

    for (final postId in allPostIds) {
      final post = _postBox.get(postId);
      if (post == null) continue;

      final filename = "${post.id}.${post.fileExt ?? 'jpg'}";
      final filePath = p.join(downloadsPath, filename);
      final file = File(filePath);

      if (await file.exists()) {
        final stat = await file.stat();
        freshList.add(DownloadedItem(
          id: post.id.toString(),
          filePath: filePath,
          filename: filename,
          creationDate: stat.modified,
        ));
      } else {
        _logger.warning(
            'File not found for post ID: $postId, removing from Hive.');
        await _postBox.delete(postId);
      }
    }

    freshList.sort((a, b) => b.creationDate.compareTo(a.creationDate));
    _downloadedItems = freshList;

    Future.microtask(() {
      if (!_isDisposed) notifyListeners();
    });
  }

  @override
  Future<void> deleteDownloadedItem(DownloadedItem item) async {
    try {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      final postId = int.tryParse(item.id);
      if (postId != null && _postBox.containsKey(postId)) {
        await _postBox.delete(postId);
      }
      _downloadedItems.removeWhere((i) => i.id == item.id);

      Future.microtask(() {
        if (!_isDisposed) notifyListeners();
      });
    } catch (e) {
      _logger.severe("Failed to delete file on Windows: $e");
    }
  }

  @override
  Future<void> cancelDownload(AppDownloadTask task) async {
    if (_cancelTokens.containsKey(task.taskId)) {
      _cancelTokens[task.taskId]?.cancel();
    }
  }

  @override
  Future<void> cancelAllDownloads() async {
    final tasksToCancel = List<AppDownloadTask>.from(_tasks);
    for (var task in tasksToCancel) {
      await cancelDownload(task);
    }
  }

  @override
  Future<void> pauseDownload(AppDownloadTask task) async {}
  @override
  Future<void> resumeDownload(AppDownloadTask task) async {}
  @override
  Future<void> retryDownload(AppDownloadTask task) async {}
  @override
  Future<void> pauseAllDownloads() async {}
  @override
  Future<void> removeTask(AppDownloadTask task) async {
    await cancelDownload(task);
  }

  @override
  void setupPhotoManagerListener() {}
  @override
  Future<void> refreshTasks() async {
    if (!_isDisposed) notifyListeners();
  }

  Future<String> _getDownloadPath() async {
    final String? customPath = await _settingsService.getDownloadPath();
    if (customPath != null && customPath.isNotEmpty) {
      final dir = Directory(customPath);
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (e) {
          _logger.severe('Failed to create custom directory: $customPath, error: $e');
        }
      }
      if (await dir.exists()) {
        _logger.info('Windows Download Notifier using custom download directory: $customPath');
        return customPath;
      }
    }
    final defaultPath = await _settingsService.getDefaultDownloadPath();
    _logger.info('Windows Download Notifier using default download directory: $defaultPath');
    return defaultPath;
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (var token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();
    super.dispose();
  }
}
