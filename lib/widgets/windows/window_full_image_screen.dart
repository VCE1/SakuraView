import 'package:flutter/material.dart';

import 'package:vce1_sakuraview/widgets/common/sakura_photo_gallery_viewer.dart';

class UserUtils {
  static String getAvatarUrl(int creatorId) {
    if (creatorId <= 0) return '';
    return 'https://yande.re/data/avatars/$creatorId.jpg';
  }

  static String getUserPageUrl(int creatorId) =>
      'https://yande.re/user/show/$creatorId';
}

class FormatUtils {
  static String formatFileSize(int fileSize) =>
      ViewerFormatUtils.fileSize(fileSize);

  static String timeAgoSinceDate(int timestamp) =>
      ViewerFormatUtils.timeAgo(timestamp);
}

enum ImageDisplayMode {
  preview,
  loadingOriginal,
  originalZoomable,
}

/// Unified, high-performance image gallery viewer for Windows & Desktop.
/// Powered by [SakuraPhotoGalleryViewer] (referencing pixes & boorusama).
class WindowsFullImageScreen extends StatelessWidget {
  final Map<String, dynamic> postData;
  final List<Map<String, dynamic>>? posts;
  final int initialIndex;
  final VoidCallback? onNextPageRequested;
  final VoidCallback? onGoToPreviousImage;
  final VoidCallback? onGoToNextImage;
  final ValueChanged<String>? onTagSelected;

  const WindowsFullImageScreen({
    super.key,
    required this.postData,
    this.posts,
    this.initialIndex = 0,
    this.onNextPageRequested,
    this.onGoToPreviousImage,
    this.onGoToNextImage,
    this.onTagSelected,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePosts = posts != null && posts!.isNotEmpty
        ? posts!
        : <Map<String, dynamic>>[postData];

    final effectiveIndex = posts != null && posts!.isNotEmpty
        ? initialIndex.clamp(0, effectivePosts.length - 1)
        : 0;

    final isLocal = postData['is_local_file'] as bool? ?? false;

    return SakuraPhotoGalleryViewer(
      posts: effectivePosts,
      initialIndex: effectiveIndex,
      isLocal: isLocal,
      onTagSelected: onTagSelected,
    );
  }
}
