import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/services/download_notification_service.dart';
import 'package:vce1_sakuraview/services/proxy_config.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';

/// 跨平台高性能并发下载引擎（连接池复用 + 分片 `.part` 原子写入 + 断线重试 + 原生通知栏进度）。
class PooledDownloadNotifier extends BaseDownloadNotifier {
  static const int maxConcurrentDownloads = 4;
  static const int _maxRetryAttempts = 3;
  static const Duration _headerTimeout = Duration(seconds: 25);
  static const Duration _chunkInactivityTimeout = Duration(seconds: 15);
  static const Duration _eofGraceTimeout = Duration(milliseconds: 300);
  static const Duration _sinkFlushTimeout = Duration(seconds: 12);

  final Logger _logger;
  final SettingsService _settingsService = SettingsService();
  final bool enableNotifications;

  final List<AppDownloadTask> _allTasks = [];
  final Set<String> _runningTaskIds = {};
  final Set<String> _pausedTaskIds = {};
  final Set<String> _canceledTaskIds = {};
  final Map<String, StreamSubscription<List<int>>> _activeSubscriptions = {};
  final Map<String, String> _taskValidators = {};

  List<DownloadedItem> _downloadedItems = [];
  bool _isLoadingGallery = false;
  bool _isListenerInitialized = false;
  bool _isDisposed = false;

  HttpClient? _httpClient;
  DateTime _lastUiSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _trailingUiSyncTimer;
  int _notificationEpoch = 0;

  // 用于通知栏单轮会话统计
  int _sessionTotalCount = 0;
  int _sessionFinishedCount = 0;
  int _sessionFailedCount = 0;
  int _activeBatchEnqueueDepth = 0;

  final Future<String> Function()? _downloadPathResolver;
  final Duration _inactivityTimeout;

  PooledDownloadNotifier({
    String loggerName = 'PooledDownloadNotifier',
    this.enableNotifications = false,
    Future<String> Function()? downloadPathResolver,
    Duration chunkInactivityTimeout = _chunkInactivityTimeout,
    bool scanOnInit = true,
  })  : _logger = Logger(loggerName),
        _downloadPathResolver = downloadPathResolver,
        _inactivityTimeout = chunkInactivityTimeout {
    if (scanOnInit) {
      scanForDownloadedImages();
    }
  }

  @override
  bool get isLoadingGallery => _isLoadingGallery;

  @override
  List<DownloadedItem> get downloadedItems => _downloadedItems;

  @override
  List<AppDownloadTask> get downloadingTasks =>
      _allTasks.where((t) => t.status.isVisibleInQueue).toList();

  @override
  int get aggregateProgressPercent {
    final active = _allTasks.where((t) => t.status.isActive).toList();
    if (_sessionTotalCount > 1 && (_sessionFinishedCount > 0 || active.isNotEmpty)) {
      final activeSum = active.fold<int>(0, (acc, t) => acc + t.progress);
      final raw = (((_sessionFinishedCount * 100) + activeSum) / _sessionTotalCount)
          .round();
      final upper = (active.isNotEmpty || _activeBatchEnqueueDepth > 0) ? 99 : 100;
      return raw.clamp(0, upper);
    }
    return super.aggregateProgressPercent;
  }

  @override
  Future<EnqueueBatchSummary> enqueueBatchDownload(
    List<Map<String, dynamic>> posts,
  ) async {
    _activeBatchEnqueueDepth++;
    try {
      return await super.enqueueBatchDownload(posts);
    } finally {
      _activeBatchEnqueueDepth =
          (_activeBatchEnqueueDepth - 1).clamp(0, 999999);
      _finalizeBatchNotificationIfIdle();
      _disposeIdleHttpClientIfDone();
      _scheduleProgressSync(force: true);
      _pumpQueue();
    }
  }

  /// 文件落地完成后的平台钩子（如 Android 通知 MediaScanner）。
  @protected
  Future<void> onFileSaved(String fullPath) async {}

  Future<HttpClient> _obtainHttpClient() async {
    if (_httpClient != null) return _httpClient!;
    _httpClient = await ProxyConfig.createNativeHttpClient(
      connectionTimeout: const Duration(seconds: 15),
      idleTimeout: const Duration(seconds: 25),
      maxConnectionsPerHost: 6,
    );
    return _httpClient!;
  }

  void _disposeIdleHttpClientIfDone() {
    final hasAnyActive = _allTasks.any((t) => t.status.isActive);
    if (!hasAnyActive) {
      _httpClient?.close(force: false);
      _httpClient = null;
    }
  }

  @override
  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData) async {
    final rawId = postData['id'];
    final postId =
        rawId is int ? rawId : int.tryParse(rawId?.toString().trim() ?? '');
    if (postId == null || postId <= 0) return EnqueueResult.failed;

    if (_allTasks.any(
      (t) =>
          (t.postData['id'] == postId || t.taskId == '$postId') &&
          t.status.isActive,
    )) {
      return EnqueueResult.alreadyInQueue;
    }

    if (enableNotifications) {
      unawaited(DownloadNotificationService.ensurePermissionOnce());
    }

    final quality = await _settingsService.getDownloadQuality();
    var workingPostData = await DownloadMetadataHelper.enrichBeforeDownload(
      postData,
      quality,
    );

    final resolved = DownloadMetadataHelper.resolveDownloadTarget(
      workingPostData,
      quality,
    );
    final url = resolved.url;
    if (url.isEmpty) return EnqueueResult.failed;
    workingPostData = resolved.postData;
    final fileName = resolved.fileName;

    final savePath = await _getDownloadPath();
    final targetFile = File(p.join(savePath, fileName));

    if (await targetFile.exists()) {
      await _syncExistingFileMetadata(postId, workingPostData, targetFile.path);
      return EnqueueResult.alreadyDownloaded;
    }

    if (_allTasks.any(
      (t) =>
          (t.postData['id'] == postId || t.taskId == '$postId') &&
          t.status.isActive,
    )) {
      return EnqueueResult.alreadyInQueue;
    }

    final saveDir = Directory(savePath);
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    // 若同 ID 之前失败过，移除旧失败条目再入队
    _allTasks.removeWhere((t) => t.taskId == '$postId');

    final task = AppDownloadTask(
      taskId: '$postId',
      filename: fileName,
      url: url,
      status: AppDownloadStatus.enqueued,
      progress: 0,
      postData: workingPostData,
      savedDir: savePath,
    );

    _allTasks.add(task);
    _sessionTotalCount++;
    _notificationEpoch++;
    _pausedTaskIds.remove(task.taskId);
    _canceledTaskIds.remove(task.taskId);

    _scheduleProgressSync(force: true);
    _pumpQueue();
    return EnqueueResult.success;
  }

  Future<void> _syncExistingFileMetadata(
    int postId,
    Map<String, dynamic> postData,
    String filePath,
  ) async {
    try {
      final postBox = Hive.box<PostHiveModel>('downloaded_posts');
      final existing = postBox.get(postId);
      if (existing == null || existing.localPath != filePath) {
        final model = PostHiveModel.fromApiMap(postData);
        model.localPath = filePath;
        await postBox.put(postId, model);
      }
      await scanForDownloadedImages();
    } catch (_) {}
  }

  void _pumpQueue() {
    if (_isDisposed) return;
    while (_runningTaskIds.length < maxConcurrentDownloads) {
      final nextIndex = _allTasks.indexWhere(
        (t) =>
            t.status == AppDownloadStatus.enqueued &&
            !_runningTaskIds.contains(t.taskId) &&
            !_pausedTaskIds.contains(t.taskId),
      );
      if (nextIndex == -1) break;
      final task = _allTasks[nextIndex];
      _runningTaskIds.add(task.taskId);
      task.status = AppDownloadStatus.running;
      task.errorMessage = null;
      _scheduleProgressSync(force: true);
      unawaited(_executeTask(task));
    }
  }

  File _partFileForTask(AppDownloadTask task) {
    if (Platform.isAndroid &&
        task.savedDir.startsWith('/storage/emulated/0/')) {
      final safeId = task.taskId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      return File(
        p.join(Directory.systemTemp.path, 'sakuraview_part_$safeId.part'),
      );
    }
    return File(p.join(task.savedDir, '${task.filename}.part'));
  }

  Future<void> _finalizePartFile(File partFile, String targetPath) async {
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    try {
      await partFile.rename(targetPath);
    } on FileSystemException {
      await partFile.copy(targetPath);
      await _safeDeleteFile(partFile);
    }
  }

  Future<void> _executeTask(AppDownloadTask task) async {
    final targetPath = p.join(task.savedDir, task.filename);
    final partFile = _partFileForTask(task);
    bool succeeded = false;
    String? lastError;

    for (int attempt = 0; attempt <= _maxRetryAttempts; attempt++) {
      if (_isDisposed ||
          _canceledTaskIds.contains(task.taskId) ||
          _pausedTaskIds.contains(task.taskId)) {
        break;
      }

      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        if (_isDisposed ||
            _canceledTaskIds.contains(task.taskId) ||
            _pausedTaskIds.contains(task.taskId)) {
          break;
        }
      }

      try {
        await _streamDownloadAttempt(
          task,
          targetPath,
          partFile,
          attempt: attempt,
        );
        succeeded = true;
        break;
      } catch (e) {
        lastError = e.toString();
        _logger.warning(
          'Download attempt ${attempt + 1} failed (${task.filename}): $e',
        );
        // 仅当无其他并发任务在运行时才强制重置连接池，避免误杀同行 99% 处的下载流
        if (attempt < _maxRetryAttempts) {
          if (_runningTaskIds.length <= 1) {
            _httpClient?.close(force: true);
            _httpClient = null;
          }
          if (attempt >= _maxRetryAttempts - 1) {
            await _safeDeleteFile(partFile);
            _taskValidators.remove(task.taskId);
          }
        }
      }
    }

    _activeSubscriptions.remove(task.taskId);
    _runningTaskIds.remove(task.taskId);
    if (succeeded || _canceledTaskIds.contains(task.taskId)) {
      _taskValidators.remove(task.taskId);
    }

    if (_isDisposed) return;

    if (_canceledTaskIds.contains(task.taskId)) {
      _canceledTaskIds.remove(task.taskId);
      _allTasks.removeWhere((t) => t.taskId == task.taskId);
      await _safeDeleteFile(partFile);
      _sessionTotalCount = (_sessionTotalCount - 1).clamp(0, 999999);
      _finalizeBatchNotificationIfIdle();
      _disposeIdleHttpClientIfDone();
      _scheduleProgressSync(force: true);
      _pumpQueue();
      return;
    }

    if (_pausedTaskIds.contains(task.taskId)) {
      task.status = AppDownloadStatus.paused;
      task.speedBytesPerSec = 0;
      _finalizeBatchNotificationIfIdle();
      _disposeIdleHttpClientIfDone();
      _scheduleProgressSync(force: true);
      _pumpQueue();
      return;
    }

    if (succeeded) {
      task.status = AppDownloadStatus.completed;
      task.progress = 100;
      task.speedBytesPerSec = 0;
      _sessionFinishedCount++;

      PostHiveModel? savedModel;
      try {
        final model = PostHiveModel.fromApiMap(task.postData);
        model.localPath = targetPath;
        final postBox = Hive.box<PostHiveModel>('downloaded_posts');
        await postBox.put(model.id, model);
        savedModel = model;
      } catch (e) {
        _logger.severe('Failed to save Hive metadata for ${task.taskId}: $e');
      }

      await _upsertCompletedItem(
        task: task,
        targetPath: targetPath,
        model: savedModel,
      );

      _allTasks.removeWhere((t) => t.taskId == task.taskId);
      // 先结算完成态、更新/取消通知栏并泵出下一个排队任务，绝不让媒体扫描阻塞完成流程
      _finalizeBatchNotificationIfIdle();
      _disposeIdleHttpClientIfDone();
      _scheduleProgressSync(force: true);
      _pumpQueue();

      unawaited(_notifyMediaScannerSafely(targetPath));
      return;
    } else {
      task.status = AppDownloadStatus.failed;
      task.speedBytesPerSec = 0;
      task.errorMessage = lastError ?? '下载失败';
      _sessionFailedCount++;
    }

    _finalizeBatchNotificationIfIdle();
    _disposeIdleHttpClientIfDone();
    _scheduleProgressSync(force: true);
    _pumpQueue();
  }

  Future<void> _upsertCompletedItem({
    required AppDownloadTask task,
    required String targetPath,
    PostHiveModel? model,
  }) async {
    try {
      final file = File(targetPath);
      final stat = await file.stat();
      final effectiveModel = model ??
          (PostHiveModel.fromApiMap(task.postData)..localPath = targetPath);
      final item = DownloadMetadataHelper.itemFromHive(
        effectiveModel,
        filePath: targetPath,
        stat: stat,
      );
      _downloadedItems.removeWhere(
        (existing) => existing.filePath == targetPath || existing.id == item.id,
      );
      _downloadedItems.insert(0, item);
    } catch (e) {
      _logger.fine('Failed to update local gallery entry: $e');
    }
  }

  Future<void> _notifyMediaScannerSafely(String targetPath) async {
    try {
      await onFileSaved(targetPath).timeout(const Duration(seconds: 4));
    } catch (e) {
      _logger.fine('Media scan timed out or skipped ($targetPath): $e');
    }
  }

  static final RegExp _contentRangeRegex = RegExp(
    r'^bytes\s+(?:(\d+)-(\d+)|\*)/(\d+|\*)$',
    caseSensitive: false,
  );

  ({int? start, int? end, int? total})? _parseContentRange(String? raw) {
    if (raw == null) return null;
    final m = _contentRangeRegex.firstMatch(raw.trim());
    if (m == null) return null;
    final start = m.group(1) != null ? int.tryParse(m.group(1)!) : null;
    final end = m.group(2) != null ? int.tryParse(m.group(2)!) : null;
    final totalStr = m.group(3);
    final total =
        (totalStr != null && totalStr != '*') ? int.tryParse(totalStr) : null;
    return (start: start, end: end, total: total);
  }

  Future<void> _streamDownloadAttempt(
    AppDownloadTask task,
    String targetPath,
    File partFile, {
    int attempt = 0,
  }) async {
    final uri = Uri.parse(task.url);
    final client = await _obtainHttpClient();
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 20));
    request.followRedirects = true;
    request.maxRedirects = 6;

    final siteId =
        (task.postData['site_id'] ?? task.postData['site'])?.toString();
    final headers = resolveSiteImageHeaders(task.url, siteId: siteId);
    headers.forEach((k, v) {
      request.headers.set(k, v);
    });
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    // 全量禁用 keep-alive 连接复用，防止首轮及重试时在 98%-99% 尾字节等待 FIN 卡死
    request.headers.set(HttpHeaders.connectionHeader, 'close');

    int resumeOffset = 0;
    if (await partFile.exists()) {
      resumeOffset = await partFile.length();
      if (resumeOffset > 0 && attempt < _maxRetryAttempts) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeOffset-');
        final validator = _taskValidators[task.taskId];
        if (validator != null && validator.isNotEmpty) {
          request.headers.set(HttpHeaders.ifRangeHeader, validator);
        }
      } else if (attempt >= _maxRetryAttempts && resumeOffset > 0) {
        await _safeDeleteFile(partFile);
        _taskValidators.remove(task.taskId);
        resumeOffset = 0;
      }
    }

    final HttpClientResponse response;
    try {
      response = await request.close().timeout(_headerTimeout);
    } on TimeoutException {
      try {
        request.abort();
      } catch (_) {}
      throw TimeoutException('响应头超时', _headerTimeout);
    }

    final contentRangeHeader =
        response.headers.value(HttpHeaders.contentRangeHeader);
    final parsedRange = _parseContentRange(contentRangeHeader);

    if (response.statusCode == 416 && resumeOffset > 0) {
      await response.drain<void>();
      final expectedTotal =
          parsedRange?.total ?? (task.totalBytes > 0 ? task.totalBytes : null);
      if (expectedTotal != null &&
          expectedTotal > 0 &&
          resumeOffset == expectedTotal) {
        task.totalBytes = expectedTotal;
        task.receivedBytes = resumeOffset;
        task.progress = 100;
        await _finalizePartFile(partFile, targetPath);
        return;
      }
      // `.part` 与服务端长度不一致，清空重试
      await _safeDeleteFile(partFile);
      _taskValidators.remove(task.taskId);
      throw const HttpException('Range 416 mismatch, resetting partial file');
    }

    final isPartial = response.statusCode == 206 && resumeOffset > 0;
    if (response.statusCode != 200 && !isPartial) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }

    if (isPartial &&
        parsedRange?.start != null &&
        parsedRange!.start != resumeOffset) {
      await response.drain<void>();
      await _safeDeleteFile(partFile);
      _taskValidators.remove(task.taskId);
      throw HttpException(
        'Content-Range offset mismatch: ${parsedRange.start} != $resumeOffset',
        uri: uri,
      );
    }

    final eTag = response.headers.value(HttpHeaders.etagHeader)?.trim();
    final lastMod =
        response.headers.value(HttpHeaders.lastModifiedHeader)?.trim();
    if (eTag != null && eTag.isNotEmpty && !eTag.startsWith('W/')) {
      _taskValidators[task.taskId] = eTag;
    } else if (lastMod != null && lastMod.isNotEmpty) {
      _taskValidators[task.taskId] = lastMod;
    }

    final baseOffset = isPartial ? resumeOffset : 0;
    final contentLength = response.contentLength;
    final totalBytes = contentLength > 0
        ? baseOffset + contentLength
        : (parsedRange?.total ??
            (parsedRange?.end != null ? parsedRange!.end! + 1 : 0));

    final wireEncoding =
        response.headers.value(HttpHeaders.contentEncodingHeader)?.toLowerCase().trim() ??
            '';
    final isCompressedWire =
        wireEncoding.isNotEmpty && wireEncoding != 'identity';

    task.totalBytes = totalBytes;
    task.receivedBytes = baseOffset;
    if (totalBytes > 0 && baseOffset > totalBytes) {
      await response.drain<void>();
      await _safeDeleteFile(partFile);
      _taskValidators.remove(task.taskId);
      throw HttpException(
        'Partial file exceeds Content-Length ($baseOffset > $totalBytes)',
        uri: uri,
      );
    }

    if (totalBytes > 0 && baseOffset == totalBytes && await partFile.exists()) {
      await response.drain<void>();
      task.progress = 100;
      await _finalizePartFile(partFile, targetPath);
      return;
    }

    final sink = partFile.openWrite(
      mode: isPartial ? FileMode.append : FileMode.write,
    );

    final completer = Completer<void>();
    var received = baseOffset;
    var windowStartBytes = received;
    final speedWatch = Stopwatch()..start();
    Timer? inactivityTimer;
    Timer? eofGraceTimer;

    late final StreamSubscription<List<int>> sub;

    void resetInactivityTimer() {
      inactivityTimer?.cancel();
      inactivityTimer = Timer(_inactivityTimeout, () {
        if (completer.isCompleted) return;
        eofGraceTimer?.cancel();
        unawaited(sub.cancel());
        try {
          request.abort();
        } catch (_) {}
        completer.completeError(
          TimeoutException(
            '数据流超过 ${_inactivityTimeout.inSeconds} 秒无响应',
            _inactivityTimeout,
          ),
        );
      });
    }

    void scheduleEofGraceIfComplete() {
      if (isCompressedWire || totalBytes <= 0 || received < totalBytes) {
        return;
      }
      inactivityTimer?.cancel();
      eofGraceTimer ??= Timer(_eofGraceTimeout, () {
        if (completer.isCompleted) return;
        inactivityTimer?.cancel();
        unawaited(sub.cancel());
        try {
          request.abort();
        } catch (_) {}
        completer.complete();
      });
    }

    resetInactivityTimer();

    sub = response.listen(
      (chunk) {
        if (_isDisposed ||
            _canceledTaskIds.contains(task.taskId) ||
            _pausedTaskIds.contains(task.taskId)) {
          inactivityTimer?.cancel();
          eofGraceTimer?.cancel();
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        task.receivedBytes = received;
        if (totalBytes > 0) {
          task.progress = ((received * 100) ~/ totalBytes).clamp(0, 99);
        }
        if (!isCompressedWire && totalBytes > 0 && received >= totalBytes) {
          scheduleEofGraceIfComplete();
        } else {
          resetInactivityTimer();
        }

        final elapsedMs = speedWatch.elapsedMilliseconds;
        if (elapsedMs >= 400) {
          final delta = received - windowStartBytes;
          final instSpeed = delta * 1000.0 / elapsedMs;
          task.speedBytesPerSec = task.speedBytesPerSec <= 0
              ? instSpeed
              : (task.speedBytesPerSec * 0.6) + (instSpeed * 0.4);
          windowStartBytes = received;
          speedWatch.reset();
          _scheduleProgressSync();
        }
      },
      onError: (Object error, StackTrace stack) {
        inactivityTimer?.cancel();
        eofGraceTimer?.cancel();
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        inactivityTimer?.cancel();
        eofGraceTimer?.cancel();
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    _activeSubscriptions[task.taskId] = sub;

    try {
      await completer.future;
      await sink.flush().timeout(_sinkFlushTimeout);
      await sink.close().timeout(_sinkFlushTimeout);
    } catch (e) {
      inactivityTimer?.cancel();
      eofGraceTimer?.cancel();
      try {
        await sink.close().timeout(const Duration(seconds: 4));
      } catch (_) {}
      rethrow;
    } finally {
      inactivityTimer?.cancel();
      eofGraceTimer?.cancel();
    }

    if (_canceledTaskIds.contains(task.taskId) ||
        _pausedTaskIds.contains(task.taskId)) {
      return;
    }

    if (!isCompressedWire && totalBytes > 0 && received < totalBytes) {
      throw HttpException(
        'Truncated stream: $received/$totalBytes bytes',
        uri: uri,
      );
    }

    task.progress = 100;
    await _finalizePartFile(partFile, targetPath);
  }

  void _scheduleProgressSync({bool force = false}) {
    if (_isDisposed) return;
    final now = DateTime.now();
    if (force || now.difference(_lastUiSyncAt).inMilliseconds >= 260) {
      _trailingUiSyncTimer?.cancel();
      _trailingUiSyncTimer = null;
      _lastUiSyncAt = now;
      notifyListeners();
      _pushProgressNotification();
      return;
    }
    _trailingUiSyncTimer ??= Timer(const Duration(milliseconds: 260), () {
      _trailingUiSyncTimer = null;
      if (_isDisposed) return;
      _lastUiSyncAt = DateTime.now();
      notifyListeners();
      _pushProgressNotification();
    });
  }

  void _pushProgressNotification() {
    if (!enableNotifications || _isDisposed) return;
    final active = _allTasks.where((t) => t.status.isActive).toList();
    if (active.isEmpty) return;

    final epoch = _notificationEpoch;
    final running =
        active.where((t) => t.status == AppDownloadStatus.running).toList();
    if (running.isEmpty &&
        active.every((t) => t.status == AppDownloadStatus.paused)) {
      if (epoch != _notificationEpoch) return;
      unawaited(
        DownloadNotificationService.updateProgress(
          title: '下载已暂停 (${active.length} 项)',
          body: '点击返回应用恢复下载',
          progress: aggregateProgressPercent,
        ),
      );
      return;
    }

    final totalCount = _sessionTotalCount.clamp(1, 999999);
    final percent = aggregateProgressPercent;
    final speed = _formatSpeed(aggregateSpeedBytesPerSec);
    final currentFile = running.isNotEmpty ? running.first.filename : active.first.filename;

    final String title;
    final String body;
    if (totalCount > 1) {
      final doneCount =
          (_sessionFinishedCount + _sessionFailedCount).clamp(0, totalCount - 1);
      title = '正在下载 (${doneCount + 1}/$totalCount)';
      body = speed.isNotEmpty ? '$currentFile · $speed · $percent%' : '$currentFile · $percent%';
    } else {
      title = '正在下载 $currentFile';
      body = speed.isNotEmpty ? '$speed · $percent%' : '$percent%';
    }

    if (epoch != _notificationEpoch) return;
    unawaited(
      DownloadNotificationService.updateProgress(
        title: title,
        body: body,
        progress: percent,
        indeterminate: percent == 0 && running.isNotEmpty,
      ),
    );
  }

  void _finalizeBatchNotificationIfIdle() {
    if (!enableNotifications) return;
    final stillActive = _allTasks.any((t) => t.status.isActive);
    if (stillActive || _activeBatchEnqueueDepth > 0) return;

    _notificationEpoch++;
    _trailingUiSyncTimer?.cancel();
    _trailingUiSyncTimer = null;

    final okCount = _sessionFinishedCount;
    final failCount = _sessionFailedCount;
    _sessionTotalCount = 0;
    _sessionFinishedCount = 0;
    _sessionFailedCount = 0;

    if (okCount == 0 && failCount == 0) {
      unawaited(DownloadNotificationService.cancelProgress());
      return;
    }
    if (failCount == 0) {
      unawaited(
        DownloadNotificationService.showComplete(
          title: '下载完成',
          body: '已成功保存 $okCount 项作品到本地图库',
        ),
      );
    } else {
      unawaited(
        DownloadNotificationService.showComplete(
          title: '下载结束',
          body: '成功 $okCount 项，失败 $failCount 项',
          isError: okCount == 0,
        ),
      );
    }
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  Future<void> _safeDeleteFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  Future<void> pauseDownload(AppDownloadTask task) async {
    _pausedTaskIds.add(task.taskId);
    task.status = AppDownloadStatus.paused;
    task.speedBytesPerSec = 0;
    await _activeSubscriptions[task.taskId]?.cancel();
    _scheduleProgressSync(force: true);
  }

  @override
  Future<void> resumeDownload(AppDownloadTask task) async {
    _pausedTaskIds.remove(task.taskId);
    _canceledTaskIds.remove(task.taskId);
    task.status = AppDownloadStatus.enqueued;
    task.errorMessage = null;
    if (_sessionTotalCount == 0) _sessionTotalCount = 1;
    _scheduleProgressSync(force: true);
    _pumpQueue();
  }

  @override
  Future<void> retryDownload(AppDownloadTask task) async {
    _pausedTaskIds.remove(task.taskId);
    _canceledTaskIds.remove(task.taskId);
    _taskValidators.remove(task.taskId);
    task.status = AppDownloadStatus.enqueued;
    task.progress = 0;
    task.receivedBytes = 0;
    task.speedBytesPerSec = 0;
    task.errorMessage = null;
    await _safeDeleteFile(_partFileForTask(task));
    if (_sessionTotalCount == 0) _sessionTotalCount = 1;
    _notificationEpoch++;
    _scheduleProgressSync(force: true);
    _pumpQueue();
  }

  @override
  Future<void> cancelDownload(AppDownloadTask task) async {
    _canceledTaskIds.add(task.taskId);
    _pausedTaskIds.remove(task.taskId);
    _taskValidators.remove(task.taskId);
    final sub = _activeSubscriptions.remove(task.taskId);
    await sub?.cancel();
    if (!_runningTaskIds.contains(task.taskId)) {
      _canceledTaskIds.remove(task.taskId);
      _allTasks.removeWhere((t) => t.taskId == task.taskId);
      await _safeDeleteFile(_partFileForTask(task));
      if (task.status.isActive && _sessionTotalCount > 0) {
        _sessionTotalCount--;
      }
      _finalizeBatchNotificationIfIdle();
      _scheduleProgressSync(force: true);
    }
  }

  @override
  Future<void> removeTask(AppDownloadTask task) => cancelDownload(task);

  @override
  Future<void> pauseAllDownloads() async {
    for (final task in List<AppDownloadTask>.from(_allTasks)) {
      if (task.status == AppDownloadStatus.running ||
          task.status == AppDownloadStatus.enqueued) {
        await pauseDownload(task);
      }
    }
  }

  @override
  Future<void> cancelAllDownloads() async {
    _notificationEpoch++;
    _trailingUiSyncTimer?.cancel();
    _trailingUiSyncTimer = null;
    for (final task in List<AppDownloadTask>.from(_allTasks)) {
      await cancelDownload(task);
    }
    _sessionTotalCount = 0;
    _sessionFinishedCount = 0;
    _sessionFailedCount = 0;
    if (enableNotifications) {
      unawaited(DownloadNotificationService.cancelProgress());
    }
  }

  @override
  Future<void> refreshTasks() async {
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
      final activeDir = await _getDownloadPath();
      final postBox = Hive.box<PostHiveModel>('downloaded_posts');
      final itemsByPath = <String, DownloadedItem>{};

      for (final key in postBox.keys.toList()) {
        final post = postBox.get(key);
        if (post == null) continue;
        final candidatePaths =
            DownloadMetadataHelper.candidatePathsForHivePost(post, activeDir);
        for (final path in candidatePaths) {
          final file = File(path);
          if (await file.exists()) {
            final stat = await file.stat();
            itemsByPath[file.path] = DownloadMetadataHelper.itemFromHive(
              post,
              filePath: file.path,
              stat: stat,
            );
            break;
          }
        }
      }

      final dir = Directory(activeDir);
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File &&
              DownloadMetadataHelper.isSupportedMediaPath(entity.path)) {
            if (!itemsByPath.containsKey(entity.path)) {
              final stat = await entity.stat();
              final base = p.basename(entity.path);
              final idPart = base.split('.').first;
              final postId = int.tryParse(idPart);
              final hivePost = postId != null ? postBox.get(postId) : null;
              itemsByPath[entity.path] = hivePost != null
                  ? DownloadMetadataHelper.itemFromHive(
                      hivePost,
                      filePath: entity.path,
                      stat: stat,
                    )
                  : DownloadedItem(
                      id: idPart,
                      filePath: entity.path,
                      filename: base,
                      creationDate: stat.modified,
                      fileSizeBytes: stat.size,
                    );
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
  Future<void> updateDownloadedPostMetadata(
    int postId,
    Map<String, dynamic> enrichedMap,
  ) async {
    if (postId <= 0) return;
    try {
      final postBox = Hive.box<PostHiveModel>('downloaded_posts');
      final existing = postBox.get(postId);
      final updated = PostHiveModel.fromApiMap(enrichedMap);
      if (existing?.localPath != null && existing!.localPath!.isNotEmpty) {
        updated.localPath = existing.localPath;
      }
      await postBox.put(postId, updated);
      await scanForDownloadedImages();
    } catch (e) {
      _logger.fine('Failed to persist enriched local metadata: $e');
    }
  }

  @override
  Future<void> deleteDownloadedItem(DownloadedItem item) async {
    await deleteDownloadedItems([item]);
  }

  @override
  Future<void> deleteDownloadedItems(List<DownloadedItem> items) async {
    if (items.isEmpty) return;
    try {
      final postBox = Hive.box<PostHiveModel>('downloaded_posts');
      final removedPaths = <String>{};
      final removedIds = <String>{};

      for (final item in items) {
        final idStr = item.filename.split('.').first;
        final postId = int.tryParse(idStr) ?? int.tryParse(item.id);
        if (postId != null && postBox.containsKey(postId)) {
          await postBox.delete(postId);
        }
        if (item.filePath.isNotEmpty) {
          final file = File(item.filePath);
          await _safeDeleteFile(file);
          removedPaths.add(item.filePath);
        }
        removedIds.add(item.id);
      }

      _downloadedItems.removeWhere(
        (a) => removedPaths.contains(a.filePath) || removedIds.contains(a.id),
      );
      if (!_isDisposed) notifyListeners();
    } catch (e) {
      _logger.severe('Error deleting downloaded items: $e');
    }
  }

  Future<String> _getDownloadPath() async {
    final customResolver = _downloadPathResolver;
    if (customResolver != null) {
      final resolved = await customResolver();
      final dir = Directory(resolved);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return resolved;
    }
    final customPath = await _settingsService.getDownloadPath();
    if (customPath != null && customPath.isNotEmpty) {
      return await _settingsService.ensureWritableDirectory(customPath);
    }
    return await _settingsService.getDefaultDownloadPath();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _trailingUiSyncTimer?.cancel();
    for (final sub in _activeSubscriptions.values) {
      sub.cancel();
    }
    _activeSubscriptions.clear();
    _httpClient?.close(force: true);
    _httpClient = null;
    super.dispose();
  }
}
