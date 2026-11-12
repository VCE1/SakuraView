import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

// 定义下载入队操作的结果
enum EnqueueResult {
  success,
  alreadyInQueue,
  alreadyDownloaded,
  failed,
}

// “下载中”任务的数据模型 (主要用于安卓)
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
      DownloadTask task, Map<String, dynamic> postData) {
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

// “已下载”项目的通用数据模型 (跨平台使用)
class DownloadedItem {
  final String id;
  final String filePath;
  final String filename;
  final DateTime creationDate;
  final int width;
  final int height;

  DownloadedItem({
    required this.id,
    required this.filePath,
    required this.filename,
    required this.creationDate,
    this.width = 0,
    this.height = 0,
  });
}

// 下载功能的抽象标准 (接口)
abstract class BaseDownloadNotifier extends ChangeNotifier {
  // --- 属性 ---
  bool get isLoadingGallery;
  List<DownloadedItem> get downloadedItems;
  List<AppDownloadTask> get downloadingTasks;

  // --- 主要方法 ---
  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData);
  Future<void> deleteDownloadedItem(DownloadedItem item);
  Future<void> scanForDownloadedImages();
  void setupPhotoManagerListener();

  // --- 任务控制 ---
  Future<void> pauseDownload(AppDownloadTask task);
  Future<void> resumeDownload(AppDownloadTask task);
  Future<void> cancelDownload(AppDownloadTask task);
  Future<void> retryDownload(AppDownloadTask task);
  Future<void> removeTask(AppDownloadTask task);

  // --- 全局控制 ---
  Future<void> pauseAllDownloads();
  Future<void> cancelAllDownloads();
  Future<void> refreshTasks();
}
