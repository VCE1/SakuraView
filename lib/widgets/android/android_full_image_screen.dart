import 'package:flutter/material.dart';

import 'package:vce1_sakuraview/widgets/common/sakura_photo_gallery_viewer.dart';

/// Legacy FormatUtils preserved for backward compatibility.
class FormatUtils {
  static String fileSize(int bytes) => ViewerFormatUtils.fileSize(bytes);
  static String timeAgo(int ts) => ViewerFormatUtils.timeAgo(ts);
  static String resolution(num? w, num? h) =>
      ViewerFormatUtils.resolution(w, h);
}

/// Unified, high-performance image gallery viewer for Android and mobile devices.
/// Powered by [SakuraPhotoGalleryViewer] (referencing pixes & boorusama).
class AndroidFullImageScreen extends StatelessWidget {
  final Map<String, dynamic> postData;
  final List<Map<String, dynamic>>? posts;
  final int initialIndex;
  final ValueChanged<String>? onTagSelected;

  const AndroidFullImageScreen({
    super.key,
    required this.postData,
    this.posts,
    this.initialIndex = 0,
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
