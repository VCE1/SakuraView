import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

/// 下载目标解析结果。
class ResolvedDownloadTarget {
  final String url;
  final String fileExt;
  final String fileName;
  final Map<String, dynamic> postData;

  const ResolvedDownloadTarget({
    required this.url,
    required this.fileExt,
    required this.fileName,
    required this.postData,
  });
}

/// 跨平台下载公共元数据与文件工具，避免 Android / Windows 实现重复代码。
class DownloadMetadataHelper {
  DownloadMetadataHelper._();

  static const Set<String> supportedMediaExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'mp4',
    'webm',
    'mkv',
  };

  static bool isSupportedMediaPath(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return supportedMediaExtensions.contains(ext);
  }

  /// 下载前按需补全原图地址、上传者与分类标签（适用于列表接口省略分类或原图地址的场景）。
  static Future<Map<String, dynamic>> enrichBeforeDownload(
    Map<String, dynamic> rawPostData,
    DownloadQuality quality, {
    Future<PostHiveModel?> Function(String siteId, String postId)? detailFetcher,
  }) async {
    final working = Map<String, dynamic>.from(rawPostData);
    final rawId = working['id'];
    final postId =
        rawId is int ? rawId : int.tryParse(rawId?.toString().trim() ?? '');
    if (postId == null || postId <= 0) return working;

    final siteId = (working['site_id'] ?? working['site'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final rawFileUrl =
        (working['file_url'] ?? working['original_url'] ?? '').toString();

    final needsZerochanFull = quality == DownloadQuality.original &&
        (rawFileUrl.contains('zerochan.net/600/') ||
            (siteId == 'zerochan' && rawFileUrl.isEmpty));
    final missingUploader =
        (working['uploader']?.toString().trim().isEmpty ?? true);

    bool hasNonEmptyList(dynamic v) => v is List && v.isNotEmpty;
    final hasAnyCategory = hasNonEmptyList(working['artist_tags']) ||
        hasNonEmptyList(working['character_tags']) ||
        hasNonEmptyList(working['copyright_tags']) ||
        hasNonEmptyList(working['meta_tags']);
    final hasRawTags =
        (working['tags']?.toString().trim().isNotEmpty ?? false);
    final needsCategories = !hasAnyCategory && hasRawTags;

    if (!needsZerochanFull && !missingUploader && !needsCategories) {
      return working;
    }

    final effectiveSiteId = siteId.isNotEmpty
        ? siteId
        : (rawFileUrl.contains('zerochan.net') ? 'zerochan' : '');
    if (effectiveSiteId.isEmpty) return working;

    if (detailFetcher == null) {
      final host = (Uri.tryParse(rawFileUrl)?.host ?? '').toLowerCase();
      if (host == '127.0.0.1' || host == 'localhost' || host == '::1') {
        return working;
      }
    }

    try {
      final PostHiveModel? detail = await Future<PostHiveModel?>(
        () => detailFetcher != null
            ? detailFetcher(effectiveSiteId, postId.toString())
            : _fetchDetailForStoredSite(effectiveSiteId, postId.toString()),
      ).timeout(const Duration(seconds: 6), onTimeout: () => null);
      if (detail == null) return working;

      final detailMap = detail.toApiMap(siteName: effectiveSiteId);
      for (final entry in detailMap.entries) {
        final val = entry.value;
        if (val == null) continue;
        if (val is String && val.trim().isEmpty) continue;
        if (val is List && val.isEmpty) continue;
        if (val is int && val == 0 && entry.key != 'score') continue;
        working[entry.key] = val;
      }
      if (detail.fileUrl != null && detail.fileUrl!.isNotEmpty) {
        working['file_url'] = detail.fileUrl!;
        working['original_url'] = detail.fileUrl!;
      }
    } catch (e, st) {
      // 详情补充失败时降级保留已有字段继续下载
      debugPrint('DownloadMetadataHelper.enrichBeforeDownload skipped: $e\n$st');
    }
    return working;
  }

  static Future<PostHiveModel?> _fetchDetailForStoredSite(
    String siteId,
    String postId,
  ) async {
    final adapter = await SiteConfigProvider.createAdapterForStoredSite(siteId);
    if (adapter == null) return null;
    try {
      return await adapter
          .getPostDetail(postId)
          .timeout(const Duration(seconds: 10));
    } finally {
      await adapter.close();
    }
  }

  /// 根据设置中的画质偏好（默认原图）解析实际下载地址与扩展名。
  static ResolvedDownloadTarget resolveDownloadTarget(
    Map<String, dynamic> rawPostData,
    DownloadQuality quality,
  ) {
    final postData = Map<String, dynamic>.from(rawPostData);
    final postId = postData['id'];
    final originalUrl =
        (postData['file_url'] ?? postData['original_url'] ?? '')
            .toString()
            .trim();
    final sampleUrl = (postData['sample_url'] ?? '').toString().trim();
    final previewUrl =
        (postData['preview_url'] ?? postData['thumbnail_url'] ?? '')
            .toString()
            .trim();

    String chosenUrl;
    if (quality == DownloadQuality.sample) {
      chosenUrl = sampleUrl.isNotEmpty
          ? sampleUrl
          : (originalUrl.isNotEmpty ? originalUrl : previewUrl);
    } else {
      chosenUrl = originalUrl.isNotEmpty
          ? originalUrl
          : (sampleUrl.isNotEmpty ? sampleUrl : previewUrl);
    }
    chosenUrl = SourceUrlResolver.ensureHttpsUrl(chosenUrl);

    var fileExt = _inferExtensionFromUrl(chosenUrl);
    if (fileExt.isEmpty) {
      fileExt = (postData['file_ext'] as String? ?? 'jpg')
          .trim()
          .toLowerCase()
          .replaceAll('.', '');
    }
    if (fileExt.isEmpty) fileExt = 'jpg';

    postData['file_ext'] = fileExt;
    final fileName = '${postId ?? 'unknown'}.$fileExt';
    return ResolvedDownloadTarget(
      url: chosenUrl,
      fileExt: fileExt,
      fileName: fileName,
      postData: postData,
    );
  }

  static String _inferExtensionFromUrl(String url) {
    if (url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    final path = uri?.path ?? url.split('?').first;
    final dotIdx = path.lastIndexOf('.');
    if (dotIdx == -1 || dotIdx == path.length - 1) return '';
    final ext = path.substring(dotIdx + 1).toLowerCase();
    if (supportedMediaExtensions.contains(ext) ||
        RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) {
      return ext;
    }
    return '';
  }

  static DownloadedItem itemFromHive(
    PostHiveModel post, {
    required String filePath,
    required FileStat stat,
  }) {
    final artistList = post.artistTags ?? const <String>[];
    final characterList = post.characterTags ?? const <String>[];
    final copyrightList = post.copyrightTags ?? const <String>[];
    final generalList = post.generalTags ?? const <String>[];
    final metaList = post.metaTags ?? const <String>[];

    return DownloadedItem(
      id: post.id.toString(),
      filePath: filePath,
      filename: p.basename(filePath),
      creationDate: stat.modified,
      width: post.width ?? 0,
      height: post.height ?? 0,
      fileSizeBytes: stat.size,
      author: post.author,
      uploader: post.uploader,
      siteName: post.siteName,
      tags: post.tags,
      artistTags: artistList,
      characterTags: characterList,
      copyrightTags: copyrightList,
      generalTags: generalList,
      metaTags: metaList,
      parentId: post.parentId,
      hasChildren: post.hasChildren ?? false,
      poolId: post.poolId,
      poolName: post.poolName,
      pixivId: post.pixivId,
      source: post.source,
      rating: post.rating,
      sampleUrl: post.sampleUrl,
      fileUrl: post.fileUrl,
      previewUrl: post.previewUrl,
      score: post.score,
      createdAt: post.createdAt,
      creatorId: post.creatorId,
    );
  }

  static List<String> candidatePathsForHivePost(
    PostHiveModel post,
    String activeDir,
  ) {
    final ext = (post.fileExt ?? 'jpg').trim();
    final idStr = post.id.toString();
    final candidates = <String>{
      if (post.localPath != null && post.localPath!.isNotEmpty) post.localPath!,
      p.join(activeDir, '$idStr.$ext'),
      if (ext != 'png') p.join(activeDir, '$idStr.png'),
      if (ext != 'jpg') p.join(activeDir, '$idStr.jpg'),
      if (ext != 'webp') p.join(activeDir, '$idStr.webp'),
    };
    return candidates.toList();
  }
}

/// Result of enqueueing a download task.
enum EnqueueResult {
  success,
  alreadyInQueue,
  alreadyDownloaded,
  failed,
}

/// Summary result of enqueueing a batch / group download.
class EnqueueBatchSummary {
  final int total;
  final int added;
  final int skippedExisting;
  final int failed;

  const EnqueueBatchSummary({
    required this.total,
    required this.added,
    required this.skippedExisting,
    required this.failed,
  });
}

/// Unified cross-platform download task status.
enum AppDownloadStatus {
  enqueued,
  running,
  paused,
  completed,
  failed,
  canceled;

  bool get isActive =>
      this == AppDownloadStatus.enqueued ||
      this == AppDownloadStatus.running ||
      this == AppDownloadStatus.paused;

  bool get isVisibleInQueue => isActive || this == AppDownloadStatus.failed;

  String get label {
    switch (this) {
      case AppDownloadStatus.enqueued:
        return '等待中';
      case AppDownloadStatus.running:
        return '下载中';
      case AppDownloadStatus.paused:
        return '已暂停';
      case AppDownloadStatus.completed:
        return '已完成';
      case AppDownloadStatus.failed:
        return '下载失败';
      case AppDownloadStatus.canceled:
        return '已取消';
    }
  }
}

/// Active / queued download task model.
class AppDownloadTask {
  String taskId;
  final String filename;
  String url;
  AppDownloadStatus status;
  int progress;
  int receivedBytes;
  int totalBytes;
  double speedBytesPerSec;
  String? errorMessage;
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
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.errorMessage,
  });

  String get fullPath => '$savedDir/$filename';

  String get formattedSpeed {
    if (speedBytesPerSec <= 0) return '';
    if (speedBytesPerSec >= 1024 * 1024) {
      return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(speedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }
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
  final String? uploader;
  final String? siteName;
  final String? tags;
  final List<String> artistTags;
  final List<String> characterTags;
  final List<String> copyrightTags;
  final List<String> generalTags;
  final List<String> metaTags;
  final int? parentId;
  final bool hasChildren;
  final int? poolId;
  final String? poolName;
  final int? pixivId;
  final String? source;
  final String? rating;
  final String? sampleUrl;
  final String? fileUrl;
  final String? previewUrl;
  final int? score;
  final int? createdAt;
  final int? creatorId;

  DownloadedItem({
    required this.id,
    required this.filePath,
    required this.filename,
    required this.creationDate,
    this.width = 0,
    this.height = 0,
    this.fileSizeBytes = 0,
    this.author,
    this.uploader,
    this.siteName,
    this.tags,
    this.artistTags = const [],
    this.characterTags = const [],
    this.copyrightTags = const [],
    this.generalTags = const [],
    this.metaTags = const [],
    this.parentId,
    this.hasChildren = false,
    this.poolId,
    this.poolName,
    this.pixivId,
    this.source,
    this.rating,
    this.sampleUrl,
    this.fileUrl,
    this.previewUrl,
    this.score,
    this.createdAt,
    this.creatorId,
  });

  bool get hasGroup =>
      hasChildren ||
      (parentId != null && parentId! > 0) ||
      (poolId != null && poolId! > 0);

  String get displayArtist {
    if (artistTags.isNotEmpty) return artistTags.join(', ');
    final a = (author ?? '').trim();
    if (a.isNotEmpty && a.toLowerCase() != 'unknown') return a;
    return '';
  }

  /// 多字段下载检索匹配（支持画师、上传者、原作/作品、角色、标签、图组 ID、父级 ID、来源链接及文件名）。
  bool matchesSearchQuery(String rawQuery, {bool onlyGroups = false}) {
    if (onlyGroups && !hasGroup) return false;
    final trimmed = rawQuery.trim().toLowerCase();
    if (trimmed.isEmpty) return true;

    final tokens = trimmed
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;

    final artistPool = [
      ...artistTags,
      if (author != null) author!,
    ].join(' ').toLowerCase();
    final uploaderPool = [
      if (uploader != null) uploader!,
      if (creatorId != null) creatorId.toString(),
    ].join(' ').toLowerCase();
    final workPool = [
      ...copyrightTags,
      ...characterTags,
    ].join(' ').toLowerCase();
    final groupPool = [
      id,
      if (parentId != null) parentId.toString(),
      if (hasGroup) 'group parent',
    ].join(' ').toLowerCase();
    final tagPool = [
      if (tags != null) tags!,
      ...generalTags,
      ...metaTags,
    ].join(' ').toLowerCase();
    final generalPool = [
      id,
      filename,
      if (siteName != null) siteName!,
      if (source != null) source!,
      artistPool,
      uploaderPool,
      workPool,
      groupPool,
      tagPool,
    ].join(' ').toLowerCase();

    for (final token in tokens) {
      if (token.startsWith('artist:') || token.startsWith('author:')) {
        final v = token.split(':').skip(1).join(':');
        if (v.isNotEmpty && !artistPool.contains(v)) return false;
      } else if (token.startsWith('uploader:') || token.startsWith('user:')) {
        final v = token.split(':').skip(1).join(':');
        if (v.isNotEmpty && !uploaderPool.contains(v)) return false;
      } else if (token.startsWith('parent:') || token.startsWith('group:')) {
        final v = token.split(':').skip(1).join(':');
        if (v.isNotEmpty && !groupPool.contains(v)) return false;
      } else if (token.startsWith('site:')) {
        final v = token.split(':').skip(1).join(':');
        if (v.isNotEmpty && !(siteName ?? '').toLowerCase().contains(v)) {
          return false;
        }
      } else {
        if (!generalPool.contains(token)) return false;
      }
    }
    return true;
  }

  /// 转换为完整帖子 Map，供详情页与全屏看图器直接展示与浏览。
  Map<String, dynamic> toApiMap() {
    final ext = filename.contains('.') ? filename.split('.').last : 'jpg';
    final effectiveTags = (tags != null && tags!.trim().isNotEmpty)
        ? tags!
        : [
            ...copyrightTags,
            ...characterTags,
            ...artistTags,
            ...generalTags,
            ...metaTags,
          ].join(' ');
    return {
      'id': int.tryParse(id) ?? 0,
      'site': siteName ?? '',
      'site_id': siteName ?? '',
      'tags': effectiveTags,
      'author': displayArtist.isNotEmpty ? displayArtist : (author ?? ''),
      'uploader': uploader ?? '',
      'creator_id': creatorId,
      'artist_tags': artistTags,
      'character_tags': characterTags,
      'copyright_tags': copyrightTags,
      'general_tags': generalTags,
      'meta_tags': metaTags,
      'tag_string_artist': artistTags.join(' '),
      'tag_string_character': characterTags.join(' '),
      'tag_string_copyright': copyrightTags.join(' '),
      'tag_string_general': generalTags.join(' '),
      'tag_string_meta': metaTags.join(' '),
      'width': width,
      'height': height,
      'file_size': fileSizeBytes,
      'file_ext': ext,
      'rating': rating ?? 'unknown',
      'score': score ?? 0,
      'parent_id': parentId,
      'has_children': hasChildren,
      if (poolId != null && poolId! > 0) 'pool_id': poolId,
      if (poolName != null && poolName!.isNotEmpty) 'pool_name': poolName,
      if (pixivId != null && pixivId! > 0) 'pixiv_id': pixivId,
      'source': source ?? '',
      'created_at': createdAt,
      'preview_url': previewUrl ?? filePath,
      'thumbnail_url': previewUrl ?? filePath,
      'sample_url': sampleUrl ?? filePath,
      'file_url': fileUrl ?? filePath,
      'original_url': fileUrl ?? filePath,
      'local_path': filePath,
      'local_file_path': filePath,
      'localPath': filePath,
      'is_local_file': true,
    };
  }
}

/// Cross-platform download manager interface.
abstract class BaseDownloadNotifier extends ChangeNotifier {
  bool get isLoadingGallery;
  List<DownloadedItem> get downloadedItems;
  List<AppDownloadTask> get downloadingTasks;

  double get aggregateSpeedBytesPerSec {
    double total = 0;
    for (final task in downloadingTasks) {
      if (task.status == AppDownloadStatus.running) {
        total += task.speedBytesPerSec;
      }
    }
    return total;
  }

  int get aggregateProgressPercent {
    final active = downloadingTasks.where((t) => t.status.isActive).toList();
    if (active.isEmpty) return 0;
    final sum = active.fold<int>(0, (acc, t) => acc + t.progress);
    return (sum / active.length).round().clamp(0, 100);
  }

  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData);

  Future<EnqueueBatchSummary> enqueueBatchDownload(
    List<Map<String, dynamic>> posts,
  ) async {
    int added = 0;
    int skipped = 0;
    int failed = 0;
    final seenIds = <int>{};
    final queue = <Map<String, dynamic>>[];
    for (final post in posts) {
      final rawId = post['id'];
      final id =
          rawId is int ? rawId : int.tryParse(rawId?.toString().trim() ?? '') ?? 0;
      if (id > 0 && !seenIds.add(id)) continue;
      queue.add(post);
    }

    for (var i = 0; i < queue.length; i += 4) {
      final chunk = queue.sublist(i, (i + 4).clamp(0, queue.length));
      final results = await Future.wait(chunk.map(enqueueDownload));
      for (final res in results) {
        switch (res) {
          case EnqueueResult.success:
            added++;
            break;
          case EnqueueResult.alreadyInQueue:
          case EnqueueResult.alreadyDownloaded:
            skipped++;
            break;
          case EnqueueResult.failed:
            failed++;
            break;
        }
      }
    }

    return EnqueueBatchSummary(
      total: queue.length,
      added: added,
      skippedExisting: skipped,
      failed: failed,
    );
  }

  Future<void> deleteDownloadedItem(DownloadedItem item);

  Future<void> deleteDownloadedItems(List<DownloadedItem> items) async {
    for (final item in List<DownloadedItem>.from(items)) {
      await deleteDownloadedItem(item);
    }
  }

  Future<void> updateDownloadedPostMetadata(
    int postId,
    Map<String, dynamic> enrichedMap,
  ) async {}

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
