import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

/// Result of enqueueing a download task.
enum EnqueueResult {
  success,
  alreadyInQueue,
  alreadyDownloaded,
  failed,
}

/// Active / queued download task model.
class AppDownloadTask {
  String taskId;
  final String filename;
  final String url;
  dynamic status;
  int progress;
  final Map<String, dynamic> postData;
  String savedDir;

  AppDownloadTask({
    required this.taskId,
    required this.filename,
    required this.url,
    required this.status,
    required this.progress,
    required this.postData,
    required this.savedDir,
  });

  factory AppDownloadTask.fromDownloaderTask(
    DownloadTask task,
    Map<String, dynamic> postData,
  ) {
    return AppDownloadTask(
      taskId: task.taskId,
      filename:
          task.filename ?? task.url.split('/').lastOrNull ?? 'unknown_file',
      url: task.url,
      status: task.status,
      progress: task.progress,
      postData: postData,
      savedDir: task.savedDir,
    );
  }

  String get fullPath => '$savedDir/$filename';
}

/// Completed download item model (cross-platform).
class DownloadedItem {
  final String id;
  final String filePath;
  final String filename;
  final DateTime creationDate;
  final int width;
  final int height;
  final int fileSizeBytes;
  final String? author;
  final String? tags;

  DownloadedItem({
    required this.id,
    required this.filePath,
    required this.filename,
    required this.creationDate,
    this.width = 0,
    this.height = 0,
    this.fileSizeBytes = 0,
    this.author,
    this.tags,
  });
}

/// Cross-platform download manager interface.
abstract class BaseDownloadNotifier extends ChangeNotifier {
  bool get isLoadingGallery;
  List<DownloadedItem> get downloadedItems;
  List<AppDownloadTask> get downloadingTasks;

  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData);
  Future<void> deleteDownloadedItem(DownloadedItem item);
  Future<void> scanForDownloadedImages();
  void setupPhotoManagerListener();

  Future<void> pauseDownload(AppDownloadTask task);
  Future<void> resumeDownload(AppDownloadTask task);
  Future<void> cancelDownload(AppDownloadTask task);
  Future<void> retryDownload(AppDownloadTask task);
  Future<void> removeTask(AppDownloadTask task);

  Future<void> pauseAllDownloads();
  Future<void> cancelAllDownloads();
  Future<void> refreshTasks();
}
