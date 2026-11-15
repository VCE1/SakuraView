import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/services/followed_tags_service.dart';
import 'package:vce1_sakuraview/services/history_service.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/common/group_posts_screen.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_video_player.dart';
import 'package:vce1_sakuraview/widgets/common/share_options_sheet.dart';
import 'package:vce1_sakuraview/widgets/common/tag_action_sheet.dart';

/// Formatter utilities for post metadata display.
class ViewerFormatUtils {
  static String fileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  static String resolution(num? w, num? h) {
    if (w == null || h == null || w <= 0 || h <= 0) return '';
    return '${w.toInt()} \u00D7 ${h.toInt()}';
  }

  static String timeAgo(int ts) {
    if (ts <= 0) return '';
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      final diff = DateTime.now().difference(date);
      if (diff.inDays > 7) return DateFormat('yyyy/MM/dd').format(date);
      if (diff.inDays > 1) return '${diff.inDays}天前';
      if (diff.inHours > 0) return '${diff.inHours}小时前';
      if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
      return '刚刚';
    } catch (_) {
      return '';
    }
  }

  static (String label, Color color) parseRating(
    String? rating, {
    String? siteId,
  }) {
    final parsed = ContentRating.parse(rating, siteId: siteId);
    switch (parsed) {
      case ContentRating.safe:
        return ('Safe 全年龄', const Color(0xFF10B981));
      case ContentRating.sensitive:
        return ('Sensitive 敏感级', const Color(0xFFF59E0B));
      case ContentRating.questionable:
        return ('Questionable 存疑级', const Color(0xFFF59E0B));
      case ContentRating.explicit:
        return ('Explicit 限制级', const Color(0xFFEF4444));
      case ContentRating.unknown:
        return ('Unknown 未知', const Color(0xFF94A3B8));
    }
  }
}

enum _ResolutionTier {
  thumbnail,
  sample,
  original,
}

/// Next-Generation Full-Featured Image Gallery Viewer
/// High performance, 3-tier progressive loading (Thumbnail -> Sample -> Master Original),
/// Telegram-style sleek frosted glass status capsule, Hero transitions, zero emojis.
class SakuraPhotoGalleryViewer extends StatefulWidget {
  final List<Map<String, dynamic>> posts;
  final int initialIndex;
  final bool isLocal;
  final ValueChanged<String>? onTagSelected;

  const SakuraPhotoGalleryViewer({
    super.key,
    required this.posts,
    this.initialIndex = 0,
    this.isLocal = false,
    this.onTagSelected,
  });

  @override
  State<SakuraPhotoGalleryViewer> createState() =>
      _SakuraPhotoGalleryViewerState();
}

class _SakuraPhotoGalleryViewerState extends State<SakuraPhotoGalleryViewer>
    with SingleTickerProviderStateMixin {
  static final Logger _log = Logger('SakuraPhotoGalleryViewer');

  late PageController _pageController;
  late int _currentIndex;
  bool _showUI = true;
  bool _tabletDetailOpen = false;
  double _dragOffsetY = 0.0;

  final Map<int, PhotoViewController> _photoControllers = {};
  final Map<int, _ResolutionTier> _activeTiers = {};
  final Map<int, bool> _originalLoading = {};
  final Map<int, bool> _originalFailed = {};
  final Map<int, String> _resolvedMasterUrls = {};

  final Map<int, ImageStream> _imageStreams = {};
  final Map<int, ImageStreamListener> _streamListeners = {};
  final Map<String, int> _userVotes = {};
  final Set<String> _votingPostKeys = {};

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex
        .clamp(0, widget.posts.isEmpty ? 0 : widget.posts.length - 1);
    _pageController = PageController(initialPage: _currentIndex);

    if (widget.posts.isNotEmpty) {
      final currentPost = widget.posts[_currentIndex];
      HistoryService.instance.addHistory(currentPost);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadPageWithSettings(_currentIndex);
        }
      });
    }
  }

  Future<void> _loadPageWithSettings(int index) async {
    if (!mounted || index < 0 || index >= widget.posts.length) return;
    _loadMediumImage(index);
    _loadVoteStateIfNeeded(index);

    bool preloadImages = true;
    bool viewOriginalByDefault = false;

    final settingsProvider =
        SettingsProvider.maybeOf(context, listen: false);
    if (settingsProvider != null) {
      if (!settingsProvider.isLoaded) {
        await settingsProvider.load();
      }
      preloadImages = settingsProvider.preloadImages;
      viewOriginalByDefault = settingsProvider.viewOriginalByDefault;
    } else {
      final service = SettingsService();
      preloadImages = await service.getPreloadImages();
      viewOriginalByDefault = await service.getViewOriginalByDefault();
    }

    if (!mounted) return;
    if (preloadImages) {
      if (index + 1 < widget.posts.length) {
        _loadMediumImage(index + 1);
      }
      if (index - 1 >= 0) {
        _loadMediumImage(index - 1);
      }
    }
    if (viewOriginalByDefault) {
      _requestOriginalImage(index);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pageController.dispose();
    for (final entry in _imageStreams.entries) {
      final listener = _streamListeners[entry.key];
      if (listener != null) {
        entry.value.removeListener(listener);
      }
    }
    for (final ctrl in _photoControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  PhotoViewController _getController(int index) {
    return _photoControllers.putIfAbsent(index, () => PhotoViewController());
  }

  bool _isCurrentZoomed() {
    final ctrl = _photoControllers[_currentIndex];
    if (ctrl == null) return false;
    final scale = ctrl.scale ?? 1.0;
    return scale > 1.05;
  }

  String _getThumbnailUrl(Map<String, dynamic> post) {
    if (post['is_local_file'] == true || widget.isLocal) {
      return (post['local_file_path'] ?? post['localPath'] ?? '') as String;
    }
    return (post['thumbnail_url'] ??
        post['preview_url'] ??
        post['sample_url'] ??
        post['file_url'] ??
        '') as String;
  }

  String _getSampleUrl(Map<String, dynamic> post) {
    if (post['is_local_file'] == true || widget.isLocal) {
      return (post['local_file_path'] ?? post['localPath'] ?? '') as String;
    }
    return (post['sample_url'] ??
        post['jpeg_url'] ??
        post['preview_url'] ??
        post['file_url'] ??
        '') as String;
  }

  String _getOrigUrl(Map<String, dynamic> post) {
    if (post['is_local_file'] == true || widget.isLocal) {
      return (post['local_file_path'] ?? post['localPath'] ?? '') as String;
    }
    return (post['file_url'] ??
        post['original_url'] ??
        post['jpeg_url'] ??
        post['sample_url'] ??
        post['preview_url'] ??
        '') as String;
  }

  void _resolveUrl(
    String url, {
    required VoidCallback onLoaded,
    VoidCallback? onError,
  }) {
    if (url.isEmpty) {
      onError?.call();
      return;
    }
    try {
      final provider = createSiteImageProvider(url);
      final stream = provider.resolve(createLocalImageConfiguration(context));
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, synchronousCall) {
          stream.removeListener(listener);
          onLoaded();
        },
        onError: (dynamic error, StackTrace? stackTrace) {
          stream.removeListener(listener);
          onError?.call();
        },
      );
      stream.addListener(listener);
    } catch (_) {
      onError?.call();
    }
  }

  /// Fast medium-resolution image loading (Sample / Preview).
  /// Responsive, low latency, low memory footprint.
  void _loadMediumImage(int index) async {
    if (index < 0 || index >= widget.posts.length) return;
    if (_activeTiers[index] == _ResolutionTier.original ||
        _activeTiers[index] == _ResolutionTier.sample) {
      return;
    }

    final post = widget.posts[index];
    final ext = post['file_ext']?.toString();
    final origCheck = _getOrigUrl(post);
    final sampleUrl = _getSampleUrl(post);

    if (SourceUrlResolver.isVideoMedia(url: origCheck, fileExt: ext) ||
        SourceUrlResolver.isVideoMedia(url: sampleUrl)) {
      _activeTiers[index] = _ResolutionTier.original;
      return;
    }

    if (SourceUrlResolver.isAnimatedMedia(url: origCheck, fileExt: ext) &&
        origCheck.isNotEmpty &&
        !SourceUrlResolver.isAnimatedMedia(url: sampleUrl)) {
      _requestOriginalImage(index);
      return;
    }

    if (post['is_local_file'] == true || widget.isLocal) {
      _activeTiers[index] = _ResolutionTier.original;
      return;
    }

    if (sampleUrl.isEmpty) {
      _activeTiers[index] = _ResolutionTier.thumbnail;
      return;
    }

    // Zerochan detail resolution: upgrade metadata (tags, dims) without auto-downloading master image
    final site = post['site']?.toString().toLowerCase() ?? '';
    final origUrl = _getOrigUrl(post);
    if (site == 'zerochan' || origUrl.contains('zerochan.net')) {
      try {
        final apiClient = context.read<SiteConfigProvider>().apiClient;
        final detail = await apiClient.getPostDetail(post['id'].toString());
        if (detail != null && mounted) {
          if (detail.fileUrl != null && detail.fileUrl!.isNotEmpty) {
            post['file_url'] = detail.fileUrl;
            post['original_url'] = detail.fileUrl;
          }
          if (detail.sampleUrl != null && detail.sampleUrl!.isNotEmpty) {
            post['sample_url'] = detail.sampleUrl;
          }
          if (detail.width != null && detail.width! > 0) {
            post['width'] = detail.width;
          }
          if (detail.height != null && detail.height! > 0) {
            post['height'] = detail.height;
          }
          if (detail.fileSize != null && detail.fileSize! > 0) {
            post['file_size'] = detail.fileSize;
          }
          if (detail.fileExt != null && detail.fileExt!.isNotEmpty) {
            post['file_ext'] = detail.fileExt;
          }
          if (detail.tags != null && detail.tags!.isNotEmpty) {
            post['tags'] = detail.tags;
          }
        }
      } catch (e) {
        _log.fine('Zerochan detail upgrade: $e');
      }
    }

    _resolveUrl(
      sampleUrl,
      onLoaded: () {
        if (mounted && _activeTiers[index] != _ResolutionTier.original) {
          setState(() {
            _activeTiers[index] = _ResolutionTier.sample;
          });
        }
      },
    );
  }

  /// On-demand master original image loading triggered exclusively by user tap.
  /// Zero silent background downloading, zero intrusive toast alerts.
  void _requestOriginalImage(int index) async {
    if (index < 0 || index >= widget.posts.length) return;
    if (_activeTiers[index] == _ResolutionTier.original) return;
    if (_originalLoading[index] == true) return;

    final post = widget.posts[index];
    final ext = post['file_ext']?.toString();
    final origCheck = _getOrigUrl(post);
    final sampleCheck = _getSampleUrl(post);
    if (SourceUrlResolver.isVideoMedia(url: origCheck, fileExt: ext) ||
        SourceUrlResolver.isVideoMedia(url: sampleCheck)) {
      setState(() => _activeTiers[index] = _ResolutionTier.original);
      return;
    }
    if (post['is_local_file'] == true || widget.isLocal) {
      setState(() => _activeTiers[index] = _ResolutionTier.original);
      return;
    }

    var origUrl = _getOrigUrl(post);
    final site = post['site']?.toString().toLowerCase() ?? '';
    if (site == 'zerochan' || origUrl.contains('zerochan.net')) {
      try {
        final apiClient = context.read<SiteConfigProvider>().apiClient;
        final detail = await apiClient.getPostDetail(post['id'].toString());
        if (detail?.fileUrl != null && detail!.fileUrl!.isNotEmpty) {
          origUrl = detail.fileUrl!;
          post['file_url'] = detail.fileUrl;
          post['original_url'] = detail.fileUrl;
        }
      } catch (e) {
        _log.fine('Zerochan original resolve: $e');
      }
    }

    if (origUrl.isEmpty) {
      _showToast('未找到原图地址');
      return;
    }

    setState(() {
      _originalLoading[index] = true;
      _originalFailed[index] = false;
    });

    _resolvedMasterUrls[index] = origUrl;

    _resolveUrl(
      origUrl,
      onLoaded: () {
        if (mounted) {
          setState(() {
            _activeTiers[index] = _ResolutionTier.original;
            _originalLoading[index] = false;
            _originalFailed[index] = false;
          });
        }
      },
      onError: () {
        if (mounted) {
          setState(() {
            _originalLoading[index] = false;
            _originalFailed[index] = true;
          });
          _showToast('原图加载失败，请重试');
        }
      },
    );
  }

  String _resolvePostSiteId(
    Map<String, dynamic> post,
    SiteConfigProvider siteProvider,
  ) {
    final explicit =
        (post['site_id'] ?? post['site'])?.toString().trim() ?? '';
    return explicit.isNotEmpty ? explicit : siteProvider.currentSourceId;
  }

  String _voteCacheKey(String siteId, String postId) => '$siteId:$postId';

  Future<void> _loadVoteStateIfNeeded(int index) async {
    if (!mounted || widget.isLocal) return;
    if (index < 0 || index >= widget.posts.length) return;
    final post = widget.posts[index];
    final postId = post['id']?.toString().trim() ?? '';
    if (postId.isEmpty) return;
    final siteProvider = context.read<SiteConfigProvider>();
    final siteId = _resolvePostSiteId(post, siteProvider);
    final adapter = siteProvider.adapterFor(siteId);
    if (!adapter.descriptor.capabilities.supportsVoting ||
        !adapter.hasWriteCredentials) {
      return;
    }
    final key = _voteCacheKey(siteId, postId);
    if (_userVotes.containsKey(key)) return;
    final state = await adapter.fetchPostVoteState(postId);
    if (!mounted || state == null) return;
    setState(() {
      _userVotes[key] = state.userVote;
      if (state.postScore != null) {
        post['score'] = state.postScore;
      }
    });
  }

  Future<void> _voteGalleryPost(
    Map<String, dynamic> post,
    int targetVote,
  ) async {
    final postId = post['id']?.toString().trim() ?? '';
    if (postId.isEmpty) return;
    final siteProvider = context.read<SiteConfigProvider>();
    final siteId = _resolvePostSiteId(post, siteProvider);
    final adapter = siteProvider.adapterFor(siteId);
    if (!adapter.descriptor.capabilities.supportsVoting) return;

    final key = _voteCacheKey(siteId, postId);
    if (_votingPostKeys.contains(key)) return;

    final prevVote = _userVotes[key] ?? 0;
    final prevScore = post['score'] is int
        ? post['score'] as int
        : int.tryParse(post['score']?.toString() ?? '') ?? 0;
    final nextVote = (prevVote == targetVote) ? 0 : targetVote;
    final optimisticScore = prevScore - prevVote + nextVote;

    setState(() {
      _votingPostKeys.add(key);
      _userVotes[key] = nextVote;
      post['score'] = optimisticScore;
    });

    try {
      final result = nextVote == 0
          ? await adapter.unvotePost(postId)
          : await adapter.votePost(postId, nextVote);
      if (!mounted) return;
      setState(() {
        _userVotes[key] = result?.userVote ?? nextVote;
        if (result?.postScore != null) {
          post['score'] = result!.postScore;
        }
      });
      _showToast(
        nextVote == 0
            ? '已取消评分投票'
            : (nextVote > 0 ? '已赞同 (+1)' : '已点踩 (-1)'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userVotes[key] = prevVote;
        post['score'] = prevScore;
      });
      _showToast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) {
        setState(() => _votingPostKeys.remove(key));
      }
    }
  }

  Future<void> _toggleGalleryFavorite(Map<String, dynamic> post) async {
    final siteProvider = context.read<SiteConfigProvider>();
    final favNotifier = context.read<FavoritesNotifier>();
    final siteId = _resolvePostSiteId(post, siteProvider);
    final adapter = widget.isLocal ? null : siteProvider.adapterFor(siteId);
    final res = await favNotifier.toggleFavoriteWithCloudSync(
      post,
      siteName: siteId.isNotEmpty ? siteId : null,
      adapter: adapter,
    );
    if (!mounted) return;
    if (res.cloudMessage != null) {
      _showToast(res.cloudMessage!);
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _onTagClicked(String tag) {
    Navigator.of(context).pop(tag);
    widget.onTagSelected?.call(tag);
  }

  void _openInBrowser(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showToast('无法在浏览器中打开链接');
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showToast('$label 已复制到剪贴板');
  }

  void _previousPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _nextPage() {
    if (_currentIndex < widget.posts.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleInfoTap(Map<String, dynamic> post) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    if (isWide) {
      setState(() {
        _tabletDetailOpen = !_tabletDetailOpen;
      });
    } else {
      _showDetailsModal(post);
    }
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      _previousPage();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _nextPage();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyF) {
      if (widget.posts.isNotEmpty) {
        _toggleGalleryFavorite(widget.posts[_currentIndex]);
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyI) {
      if (widget.posts.isNotEmpty) {
        _handleInfoTap(widget.posts[_currentIndex]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              const Text('无可查看的图片', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    final post = widget.posts[_currentIndex];
    final dragProgress = (_dragOffsetY / 400).clamp(0.0, 1.0);
    final bgAlpha = (1.0 - dragProgress).clamp(0.0, 1.0);
    final currentScale = (1.0 - (_dragOffsetY / 1200)).clamp(0.78, 1.0);
    final isWide = MediaQuery.of(context).size.width >= 800;

    final galleryView = Stack(
      children: [
        // Pull-down dismiss drag detector
        GestureDetector(
          onVerticalDragUpdate: (details) {
            if (_isCurrentZoomed()) return;
            setState(() {
              _dragOffsetY += details.delta.dy;
              if (_dragOffsetY < 0) _dragOffsetY = 0;
            });
          },
          onVerticalDragEnd: (details) {
            if (_dragOffsetY > 110 || (details.primaryVelocity ?? 0) > 650) {
              Navigator.of(context).maybePop();
            } else {
              setState(() {
                _dragOffsetY = 0.0;
              });
            }
          },
          child: Transform.translate(
            offset: Offset(0, _dragOffsetY),
            child: Transform.scale(
              scale: currentScale,
              child: PhotoViewGallery.builder(
                pageController: _pageController,
                scrollPhysics: widget.posts.length <= 1
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                itemCount: widget.posts.length,
                gaplessPlayback: true,
                builder: (context, index) {
                  final item = widget.posts[index];
                  final isLocal =
                      item['is_local_file'] == true || widget.isLocal;
                  final ext = item['file_ext']?.toString();
                  final rawOrig = _getOrigUrl(item);
                  final rawSample = _getSampleUrl(item);
                  final isVideoItem = SourceUrlResolver.isVideoMedia(
                        url: rawOrig,
                        fileExt: ext,
                      ) ||
                      SourceUrlResolver.isVideoMedia(url: rawSample) ||
                      (isLocal && SourceUrlResolver.isVideoMedia(url: rawOrig));

                  final postId = item['id']?.toString() ?? '$index';
                  final site = item['site_id']?.toString() ??
                      item['site']?.toString() ??
                      'post';
                  final heroTag = 'post_hero_${site}_$postId';

                  if (isVideoItem) {
                    final playableUrl = isLocal
                        ? rawOrig
                        : (SourceUrlResolver.isVideoMedia(url: rawOrig)
                            ? rawOrig
                            : rawSample);
                    return PhotoViewGalleryPageOptions.customChild(
                      child: SakuraVideoPlayer(
                        videoUrl: playableUrl,
                        posterUrl: _getThumbnailUrl(item),
                        siteId: site,
                        autoPlay: index == _currentIndex,
                        looping: true,
                        compact: false,
                        onTapBackground: () {
                          setState(() {
                            _showUI = !_showUI;
                          });
                        },
                      ),
                      initialScale: PhotoViewComputedScale.contained,
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.contained,
                      heroAttributes: (index == _currentIndex ||
                              index == widget.initialIndex)
                          ? PhotoViewHeroAttributes(tag: heroTag)
                          : null,
                    );
                  }

                  final currentTier =
                      _activeTiers[index] ?? _ResolutionTier.thumbnail;

                  final String effectiveUrl;
                  if (isLocal) {
                    effectiveUrl = rawOrig;
                  } else {
                    switch (currentTier) {
                      case _ResolutionTier.original:
                        effectiveUrl = _resolvedMasterUrls[index] ?? rawOrig;
                        break;
                      case _ResolutionTier.sample:
                        effectiveUrl = rawSample;
                        break;
                      case _ResolutionTier.thumbnail:
                        effectiveUrl = _getThumbnailUrl(item);
                        break;
                    }
                  }

                  final ImageProvider provider;
                  if (isLocal && File(effectiveUrl).existsSync()) {
                    provider = FileImage(File(effectiveUrl));
                  } else {
                    provider = createSiteImageProvider(
                      effectiveUrl,
                      siteId: (item['site_id'] ?? item['site'])?.toString(),
                    );
                  }

                  return PhotoViewGalleryPageOptions(
                    controller: _getController(index),
                    imageProvider: provider,
                    filterQuality: FilterQuality.medium,
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained * 0.8,
                    maxScale: PhotoViewComputedScale.covered * 4.5,
                    heroAttributes: (index == _currentIndex ||
                            index == widget.initialIndex)
                        ? PhotoViewHeroAttributes(tag: heroTag)
                        : null,
                    onTapUp: (_, __, ___) {
                      setState(() {
                        _showUI = !_showUI;
                      });
                    },
                    scaleStateCycle: (actual) {
                      _loadMediumImage(index);
                      switch (actual) {
                        case PhotoViewScaleState.initial:
                          return PhotoViewScaleState.covering;
                        default:
                          return PhotoViewScaleState.initial;
                      }
                    },
                  );
                },
                loadingBuilder: (_, event) => const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white70,
                    ),
                  ),
                ),
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _dragOffsetY = 0.0;
                  });
                  if (index >= 0 && index < widget.posts.length) {
                    HistoryService.instance.addHistory(widget.posts[index]);
                    _loadPageWithSettings(index);
                  }
                },
                backgroundDecoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
              ),
            ),
          ),
        ),

        // Top action bar (animated overlay，专注看图，移除左右翻页悬浮按钮与占位控件)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: _showUI ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !_showUI,
              child: _buildTopBar(post),
            ),
          ),
        ),
      ],
    );

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKey(event),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            if (event.scrollDelta.dy > 0) {
              _nextPage();
            } else if (event.scrollDelta.dy < 0) {
              _previousPage();
            }
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black.withValues(alpha: bgAlpha),
          body: isWide && _tabletDetailOpen
              ? Row(
                  children: [
                    Expanded(
                      child: galleryView,
                    ),
                    _TabletDetailPane(
                      post: post,
                      onClose: () => setState(() => _tabletDetailOpen = false),
                      onTagTap: _onTagClicked,
                    ),
                  ],
                )
              : galleryView,
        ),
      ),
    );
  }

  Widget _buildTopBar(Map<String, dynamic> post) {
    final topPadding = MediaQuery.of(context).padding.top;
    final postIdStr = post['id']?.toString() ?? '';
    final siteProvider = context.watch<SiteConfigProvider>();
    final siteId = _resolvePostSiteId(post, siteProvider);
    final adapter = widget.isLocal ? null : siteProvider.adapterFor(siteId);
    final supportsVoting =
        !widget.isLocal && (adapter?.descriptor.capabilities.supportsVoting ?? false);
    final voteKey = _voteCacheKey(siteId, postIdStr);
    final userVote = _userVotes[voteKey] ?? 0;
    final scoreValue = post['score'] is int
        ? post['score'] as int
        : int.tryParse(post['score']?.toString() ?? '') ?? 0;

    final isOriginal = _activeTiers[_currentIndex] == _ResolutionTier.original;
    final isLoadingOriginal = _originalLoading[_currentIndex] == true;

    final favNotifier = context.watch<FavoritesNotifier>();
    final favKey = postIdStr.isNotEmpty
        ? postIdStr
        : (post['file_url']?.toString() ?? '');
    final isFav = favNotifier.isFavorite(favKey);

    final downloadNotifier = context.watch<BaseDownloadNotifier>();
    final isDownloaded =
        downloadNotifier.downloadedItems.any((it) => it.id == postIdStr);

    return Container(
      padding: EdgeInsets.fromLTRB(12, topPadding + 6, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.28),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.black38,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 22,
              ),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: 10),
          if (postIdStr.isNotEmpty)
            Expanded(
              child: Text(
                'POST #$postIdStr',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const Spacer(),

          if (supportsVoting && postIdStr.isNotEmpty) ...[
            Material(
              color: Colors.black38,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: userVote > 0 ? '取消赞同' : '赞同 +1',
                      icon: Icon(
                        userVote > 0
                            ? Icons.thumb_up_rounded
                            : Icons.thumb_up_outlined,
                        size: 16,
                        color: userVote > 0
                            ? const Color(0xFFFF88B5)
                            : Colors.white70,
                      ),
                      onPressed: () => _voteGalleryPost(post, 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        '$scoreValue',
                        style: TextStyle(
                          color: userVote > 0
                              ? const Color(0xFFFF88B5)
                              : (userVote < 0
                                  ? const Color(0xFFFCA5A5)
                                  : Colors.white),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 34,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: userVote < 0 ? '取消点踩' : '点踩 -1',
                      icon: Icon(
                        userVote < 0
                            ? Icons.thumb_down_rounded
                            : Icons.thumb_down_outlined,
                        size: 16,
                        color: userVote < 0
                            ? const Color(0xFFFCA5A5)
                            : Colors.white70,
                      ),
                      onPressed: () => _voteGalleryPost(post, -1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],

          // 1. HD 原图加载
          Material(
            color: Colors.black38,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: isLoadingOriginal
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isOriginal ? Icons.hd_rounded : Icons.hd_outlined,
                      color: isOriginal
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white70,
                      size: 21,
                    ),
              tooltip: isOriginal ? '已显示原图' : '加载高清原图',
              onPressed: () {
                if (isOriginal) {
                  _showToast('当前已是高清原图');
                } else if (!isLoadingOriginal) {
                  _requestOriginalImage(_currentIndex);
                }
              },
            ),
          ),
          const SizedBox(width: 4),

          // 2. 收藏（支持 Danbooru 云端双向同步）
          Material(
            color: Colors.black38,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: Icon(
                isFav
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: isFav ? const Color(0xFFFF4B72) : Colors.white70,
                size: 21,
              ),
              tooltip: isFav ? '取消收藏' : '添加收藏',
              onPressed: () => _toggleGalleryFavorite(post),
            ),
          ),
          const SizedBox(width: 4),

          // 3. 下载
          Material(
            color: Colors.black38,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: Icon(
                isDownloaded
                    ? Icons.check_circle_rounded
                    : Icons.download_rounded,
                color: isDownloaded ? const Color(0xFF10B981) : Colors.white70,
                size: 21,
              ),
              tooltip: isDownloaded ? '已在相册中' : '下载',
              onPressed: () async {
                if (isDownloaded) {
                  _showToast('该图片已在下载目录中');
                } else {
                  final res = await context
                      .read<BaseDownloadNotifier>()
                      .enqueueDownload(post);
                  switch (res) {
                    case EnqueueResult.success:
                      _showToast('已加入下载队列');
                      break;
                    case EnqueueResult.alreadyDownloaded:
                      _showToast('该图片已存在');
                      break;
                    case EnqueueResult.alreadyInQueue:
                      _showToast('该图片已在下载队列中');
                      break;
                    case EnqueueResult.failed:
                      _showToast('加入下载队列失败');
                      break;
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 4),

          // 4. 精简三点菜单（含明确的分享当前帖子功能）
          Material(
            color: Colors.black38,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Colors.white,
                size: 20,
              ),
              color: const Color(0xFF1E212B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (value) async {
                final postIdInt = int.tryParse(postIdStr) ?? 0;
                final canonicalPost = SourceUrlResolver.canonicalPostUrl(
                  siteId: siteId,
                  postId: postIdInt,
                );
                final origUrl = _getOrigUrl(post);

                switch (value) {
                  case 'share_post':
                    final shareText = SourceUrlResolver.formatShareText(
                      postId: postIdInt,
                      canonicalPostUrl: canonicalPost,
                      fallbackUrl: origUrl,
                    );
                    final localPath = (post['local_file_path'] ??
                            post['localPath'] ??
                            post['local_path'])
                        ?.toString();
                    await showShareOptionsSheet(
                      context: context,
                      shareText: shareText,
                      subject: 'POST #$postIdInt',
                      linkToCopy:
                          canonicalPost.isNotEmpty ? canonicalPost : origUrl,
                      localFilePath: localPath,
                    );
                    break;
                  case 'copy_share_post':
                    final shareText = SourceUrlResolver.formatShareText(
                      postId: postIdInt,
                      canonicalPostUrl: canonicalPost,
                      fallbackUrl: origUrl,
                    );
                    _copyToClipboard(shareText, '分享内容');
                    break;
                  case 'info':
                    _handleInfoTap(post);
                    break;
                  case 'copy_image_url':
                    _copyToClipboard(origUrl, '原图链接');
                    break;
                  case 'browser':
                    final sourceFallback = SourceUrlResolver.normalizeDisplaySource(
                      post['source'] as String?,
                    );
                    final target = canonicalPost.isNotEmpty
                        ? canonicalPost
                        : (sourceFallback.isNotEmpty ? sourceFallback : origUrl);
                    _openInBrowser(target);
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'share_post',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, size: 18, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('分享当前帖子', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'copy_share_post',
                  child: Row(
                    children: [
                      Icon(Icons.copy_all_rounded, size: 18, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('复制分享内容', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'copy_image_url',
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, size: 18, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('复制原图链接', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'info',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('查看详情', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'browser',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_browser_rounded, size: 18, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('在浏览器中打开', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailsModal(Map<String, dynamic> post) {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (modalCtx) => _PostDetailSheet(
        post: post,
        onTagTap: (tag) {
          Navigator.of(modalCtx).pop();
          _onTagClicked(tag);
        },
      ),
    );
  }
}

/// Tablet side-by-side detail pane (35% width or ~380px docked).
class _TabletDetailPane extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onClose;
  final ValueChanged<String> onTagTap;

  const _TabletDetailPane({
    required this.post,
    required this.onClose,
    required this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final totalWidth = MediaQuery.of(context).size.width;
    final paneWidth = (totalWidth * 0.36).clamp(280.0, 360.0);

    return Container(
      width: paneWidth,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.96),
        border: Border(
          left: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: SafeArea(
        child: _PostDetailBody(
          post: post,
          isSheet: false,
          onClose: onClose,
          onTagTap: onTagTap,
        ),
      ),
    );
  }
}

/// Rich metadata, categorized tag chips modal bottom sheet.
class _PostDetailSheet extends StatelessWidget {
  final Map<String, dynamic> post;
  final ValueChanged<String> onTagTap;

  const _PostDetailSheet({
    required this.post,
    required this.onTagTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.94,
      builder: (context, scrollCtrl) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: cs.surface.withValues(alpha: 0.94),
              child: _PostDetailBody(
                post: post,
                scrollController: scrollCtrl,
                isSheet: true,
                onTagTap: onTagTap,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shared post details body with zero emojis.
class _PostDetailBody extends StatelessWidget {
  final Map<String, dynamic> post;
  final ScrollController? scrollController;
  final bool isSheet;
  final VoidCallback? onClose;
  final ValueChanged<String> onTagTap;

  const _PostDetailBody({
    required this.post,
    this.scrollController,
    required this.isSheet,
    this.onClose,
    required this.onTagTap,
  });

  static Map<String, List<String>> _categorizeTags(Map<String, dynamic> p) {
    final res = <String, List<String>>{
      'artist': [],
      'character': [],
      'copyright': [],
      'general': [],
    };

    void addFromListOrStr(dynamic raw, String cat) {
      if (raw is List) {
        for (final item in raw) {
          final t = item.toString().trim();
          if (t.isNotEmpty && !res[cat]!.contains(t)) {
            res[cat]!.add(t);
          }
        }
        return;
      }
      if (raw is String && raw.trim().isNotEmpty) {
        for (final t in raw.trim().split(RegExp(r'\s+'))) {
          if (t.isNotEmpty && !res[cat]!.contains(t)) {
            res[cat]!.add(t);
          }
        }
      }
    }

    addFromListOrStr(p['artist_tags'] ?? p['tag_string_artist'], 'artist');
    addFromListOrStr(
      p['character_tags'] ?? p['tag_string_character'],
      'character',
    );
    addFromListOrStr(
      p['copyright_tags'] ?? p['tag_string_copyright'],
      'copyright',
    );
    addFromListOrStr(p['general_tags'] ?? p['tag_string_general'], 'general');

    final rawAll = (p['tags'] as String? ?? '').trim();
    if (rawAll.isNotEmpty) {
      for (final tag
          in rawAll.split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
        if (res.values.any((list) => list.contains(tag))) continue;
        final lower = tag.toLowerCase();
        if (lower.contains('(artist)') ||
            lower.contains('(mangaka)') ||
            lower.startsWith('artist:')) {
          res['artist']!.add(tag);
        } else if (lower.contains('(character)') ||
            lower.contains('(person)') ||
            lower.startsWith('character:')) {
          res['character']!.add(tag);
        } else if (lower.contains('(series)') ||
            lower.contains('(cosplay)') ||
            lower.contains('(game)') ||
            lower.startsWith('copyright:')) {
          res['copyright']!.add(tag);
        } else {
          res['general']!.add(tag);
        }
      }
    }

    return res;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final siteId = (post['site_id'] ?? post['site'])?.toString();
    final (ratingLabel, _) = ViewerFormatUtils.parseRating(
      post['rating'] as String?,
      siteId: siteId,
    );

    final resStr = ViewerFormatUtils.resolution(
      post['width'] as num?,
      post['height'] as num?,
    );
    final sizeStr = ViewerFormatUtils.fileSize(
      post['file_size'] as int? ?? 0,
    );
    final extStr = (post['file_ext'] as String? ?? '').toUpperCase();
    final timeStr = ViewerFormatUtils.timeAgo(
      post['created_at'] as int? ?? 0,
    );
    final uploaderStr = (post['uploader'] as String? ?? '').trim();
    final postId = post['id']?.toString() ?? '';
    final hasChildren = post['has_children'] == true;

    final tagsMap = _categorizeTags(post);
    final artistStr = tagsMap['artist']!.join(', ');
    final rawSite = siteId ?? 'yandere';
    final canonicalPost = SourceUrlResolver.canonicalPostUrl(
      siteId: rawSite,
      postId: int.tryParse(postId) ?? 0,
    );
    final normalizedSources = SourceUrlResolver.normalizeSourceUrls(
      post['source'] as String?,
    );

    return SelectionArea(
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
        if (isSheet) ...[
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Header row: Post ID & Rating chip & Optional close button
        Row(
          children: [
            Expanded(
              child: Text(
                'POST #$postId',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                ratingLabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!isSheet && onClose != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: '关闭',
                onPressed: onClose,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Clean unified metrics（严格区分作者与上传者）
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            if (resStr.isNotEmpty)
              _buildMetricText(context, '分辨率', resStr),
            if (sizeStr.isNotEmpty)
              _buildMetricText(context, '大小',
                  extStr.isNotEmpty ? '$sizeStr ($extStr)' : sizeStr),
            if (artistStr.isNotEmpty)
              _buildMetricText(context, '作者', artistStr),
            if (uploaderStr.isNotEmpty)
              _buildMetricText(context, '上传者', uploaderStr),
            if (timeStr.isNotEmpty)
              _buildMetricText(context, '时间', timeStr),
          ],
        ),

        if (hasChildren) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.collections_bookmark_rounded, size: 16),
            label: const Text('关联图组', style: TextStyle(fontSize: 13)),
            onPressed: () {
              Navigator.of(context).push(
                SakuraPageRoute(
                  builder: (_) => GroupPostsScreen(parentPost: post),
                ),
              );
            },
          ),
        ],

        if (canonicalPost.isNotEmpty || normalizedSources.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canonicalPost.isNotEmpty)
                  _buildCopyableLinkRow(context, '帖子链接', canonicalPost),
                for (final src in normalizedSources)
                  _buildCopyableLinkRow(context, '作品来源', src),
              ],
            ),
          ),
        ],

        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 12),

        // 严格顺序：原作 -> 角色 -> 作者 -> 常规标签
        _buildTagSection(
          context,
          icon: Icons.movie_outlined,
          title: '原作',
          tags: tagsMap['copyright']!,
        ),
        _buildTagSection(
          context,
          icon: Icons.person_outline,
          title: '角色',
          tags: tagsMap['character']!,
        ),
        _buildTagSection(
          context,
          icon: Icons.palette_outlined,
          title: '作者',
          tags: tagsMap['artist']!,
        ),
        _buildTagSection(
          context,
          icon: Icons.label_outline,
          title: '标签',
          tags: tagsMap['general']!,
        ),
      ],
    ),
  );
  }

  Widget _buildCopyableLinkRow(
    BuildContext context,
    String label,
    String value,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: cs.primary,
              decoration: value.startsWith('http')
                  ? TextDecoration.underline
                  : TextDecoration.none,
            ),
          ),
        ),
        IconButton(
          tooltip: '复制$label',
          icon: Icon(
            Icons.content_copy_rounded,
            size: 15,
            color: cs.onSurfaceVariant,
          ),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: const EdgeInsets.all(4),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('已复制$label'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
            }
          },
        ),
      ],
    );
  }

  Widget _buildMetricText(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: cs.outline,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildTagSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> tags,
  }) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.map((t) {
              return ListenableBuilder(
                listenable: Listenable.merge([
                  FollowedTagsService.instance,
                  BlacklistService.instance,
                ]),
                builder: (context, _) {
                  final isFollowed = FollowedTagsService.instance.isFollowed(t);
                  final isBlocked = BlacklistService.instance.isBlocked(t);
                  return GestureDetector(
                    onLongPress: () => showTagActionSheet(
                      context,
                      t,
                      onSearchTag: () => onTagTap(t),
                    ),
                    onSecondaryTap: () => showTagActionSheet(
                      context,
                      t,
                      onSearchTag: () => onTagTap(t),
                    ),
                    child: ActionChip(
                      avatar: isBlocked
                          ? Icon(Icons.block_rounded, size: 14, color: cs.error)
                          : (isFollowed
                              ? Icon(Icons.star_rounded,
                                  size: 14, color: cs.primary)
                              : null),
                      label: Text(
                        t,
                        style: TextStyle(
                          fontSize: 12,
                          color: isBlocked ? cs.error : cs.onSurface,
                          decoration:
                              isBlocked ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      backgroundColor: cs.surfaceContainerHighest,
                      side: BorderSide(
                        color: isFollowed
                            ? cs.primary.withValues(alpha: 0.45)
                            : cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      onPressed: () => onTagTap(t),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
