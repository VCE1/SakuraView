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

import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/common/group_posts_screen.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';

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
      if (diff.inDays == 1) return '昨天';
      if (diff.inHours > 1) return '${diff.inHours}小时前';
      if (diff.inHours == 1) return '1小时前';
      if (diff.inMinutes > 1) return '${diff.inMinutes}分钟前';
      return '刚刚';
    } catch (_) {
      return '';
    }
  }

  static (String label, Color color) parseRating(String? rating) {
    final r = (rating ?? '').toLowerCase().trim();
    if (r == 's' || r == 'g' || r == 'safe' || r == 'general') {
      return ('Safe 全年龄', const Color(0xFF10B981));
    }
    if (r == 'q' || r == 'sensitive' || r == 'questionable') {
      return ('Questionable 微敏感', const Color(0xFFF59E0B));
    }
    if (r == 'e' || r == 'explicit') {
      return ('Explicit 限制级', const Color(0xFFEF4444));
    }
    return ('Unknown 未知', Colors.grey);
  }
}

/// A high-performance, mature image gallery viewer inspired by Pixes & Boorusama.
///
/// Features:
/// - Smooth multi-image horizontal swipe gallery with [PhotoViewGallery.builder].
/// - Side navigation buttons (Chevrons) and mouse wheel support inspired by pixes.
/// - Progressive original image loading: renders preview/sample immediately (0ms delay),
///   allows non-blocking background original loading with percentage indicator.
/// - Fluid gestures: double-tap zoom (1x -> 2.5x -> 1x), pinch zoom, tap to toggle
///   immersive mode, and pull-down drag-to-dismiss.
/// - Glassmorphism floating top bar & bottom capsule actions.
/// - Rich metadata & categorized tags sheet (Artist, Character, Copyright, General).
/// - Keyboard shortcuts for desktop and tablet productivity.
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

class _SakuraPhotoGalleryViewerState extends State<SakuraPhotoGalleryViewer> {
  static final Logger _log = Logger('GalleryViewer');

  late final PageController _pageController;
  late int _currentIndex;
  final FocusNode _focusNode = FocusNode();

  bool _showUI = true;
  double _dragOffsetY = 0.0;

  // Progressive original image state per post index
  final Map<int, bool> _originalLoaded = {};
  final Map<int, bool> _originalLoading = {};
  final Map<int, double?> _originalProgress = {};
  final Map<int, ImageStream> _imageStreams = {};
  final Map<int, ImageStreamListener> _streamListeners = {};

  final Map<int, PhotoViewController> _photoControllers = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex
        .clamp(0, widget.posts.isEmpty ? 0 : widget.posts.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
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

  String _getPreviewUrl(Map<String, dynamic> post) {
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
            post['jpeg_url'] ??
            post['sample_url'] ??
            post['preview_url'] ??
            '') as String;
  }

  bool _hasOriginalAvailable(Map<String, dynamic> post) {
    final preview = _getPreviewUrl(post);
    final orig = _getOrigUrl(post);
    return orig.isNotEmpty && orig != preview;
  }

  void _loadOriginal(int index) async {
    if (_originalLoading[index] == true || _originalLoaded[index] == true) return;
    if (index < 0 || index >= widget.posts.length) return;

    final post = widget.posts[index];
    var origUrl = _getOrigUrl(post);
    if (origUrl.isEmpty) {
      _showToast('原图链接不可用');
      return;
    }

    final localConfig = createLocalImageConfiguration(context);

    setState(() {
      _originalLoading[index] = true;
      _originalProgress[index] = 0.0;
    });

    // Zerochan detail resolution if URL points to 600 thumbnail
    if (origUrl.contains('zerochan.net/600/')) {
      try {
        if (mounted) {
          final apiClient = context.read<SiteConfigProvider>().apiClient;
          final detail = await apiClient.getPostDetail(post['id'].toString());
          if (detail != null &&
              detail.fileUrl != null &&
              detail.fileUrl!.isNotEmpty &&
              mounted) {
            origUrl = detail.fileUrl!;
            post['file_url'] = detail.fileUrl;
            if (detail.fileSize != null) post['file_size'] = detail.fileSize;
            if (detail.fileExt != null) post['file_ext'] = detail.fileExt;
          }
        }
      } catch (e) {
        _log.fine('Zerochan detail upgrade: $e');
      }
    }

    try {
      final provider = createSiteImageProvider(origUrl);
      final stream = provider.resolve(localConfig);
      _imageStreams[index] = stream;

      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (mounted) {
            setState(() {
              _originalLoaded[index] = true;
              _originalLoading[index] = false;
              _originalProgress[index] = null;
            });
            _showToast('原图载入完成');
          }
        },
        onChunk: (ImageChunkEvent event) {
          if (mounted &&
              event.expectedTotalBytes != null &&
              event.expectedTotalBytes! > 0) {
            setState(() {
              _originalProgress[index] = (event.cumulativeBytesLoaded /
                      event.expectedTotalBytes!)
                  .clamp(0.0, 1.0);
            });
          }
        },
        onError: (dynamic error, StackTrace? stackTrace) {
          if (mounted) {
            setState(() {
              _originalLoading[index] = false;
              _originalProgress[index] = null;
            });
            _showToast('原图载入失败');
          }
        },
      );

      _streamListeners[index] = listener;
      stream.addListener(listener);
    } catch (e) {
      if (mounted) {
        setState(() {
          _originalLoading[index] = false;
          _originalProgress[index] = null;
        });
        _showToast('原图载入失败: $e');
      }
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
    if (widget.onTagSelected != null) {
      widget.onTagSelected!(tag);
      Navigator.of(context).pop(tag);
    } else {
      Navigator.of(context).pop(tag);
    }
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

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      _previousPage();
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _nextPage();
    } else if (key == LogicalKeyboardKey.keyO) {
      _loadOriginal(_currentIndex);
    } else if (key == LogicalKeyboardKey.keyF) {
      if (widget.posts.isNotEmpty) {
        context
            .read<FavoritesNotifier>()
            .toggleFavorite(widget.posts[_currentIndex]);
      }
    } else if (key == LogicalKeyboardKey.keyI) {
      if (widget.posts.isNotEmpty) {
        _showDetailsModal(widget.posts[_currentIndex]);
      }
    }
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

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        _handleKey(event);
        return KeyEventResult.handled;
      },
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
          body: Stack(
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
                  if (_dragOffsetY > 110 ||
                      (details.primaryVelocity ?? 0) > 650) {
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
                      scrollPhysics: const BouncingScrollPhysics(),
                      itemCount: widget.posts.length,
                      builder: (context, index) {
                        final item = widget.posts[index];
                        final isLocal =
                            item['is_local_file'] == true || widget.isLocal;
                        final isOriginal = _originalLoaded[index] == true;
                        final previewUrl = _getPreviewUrl(item);
                        final origUrl = _getOrigUrl(item);
                        final effectiveUrl = isOriginal ? origUrl : previewUrl;

                        final ImageProvider provider;
                        if (isLocal) {
                          provider = FileImage(File(effectiveUrl));
                        } else {
                          provider = createSiteImageProvider(effectiveUrl);
                        }

                        return PhotoViewGalleryPageOptions(
                          controller: _getController(index),
                          imageProvider: provider,
                          initialScale: PhotoViewComputedScale.contained,
                          minScale: PhotoViewComputedScale.contained * 0.8,
                          maxScale: PhotoViewComputedScale.covered * 4.5,
                          heroAttributes: PhotoViewHeroAttributes(
                            tag: 'post_${item['id']}_$index',
                          ),
                          onTapUp: (_, __, ___) {
                            setState(() {
                              _showUI = !_showUI;
                            });
                          },
                          scaleStateCycle: (actual) {
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
                        child: SakuraLoader(size: 32),
                      ),
                      onPageChanged: (index) {
                        setState(() {
                          _currentIndex = index;
                          _dragOffsetY = 0.0;
                        });
                      },
                      backgroundDecoration: const BoxDecoration(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),

              // Side navigation buttons (Chevrons inspired by Pixes)
              if (_currentIndex > 0)
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _showUI ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: IgnorePointer(
                        ignoring: !_showUI,
                        child: Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            icon: const Icon(Icons.chevron_left_rounded,
                                color: Colors.white, size: 28),
                            tooltip: '上一张',
                            onPressed: _previousPage,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (_currentIndex < widget.posts.length - 1)
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _showUI ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 220),
                      child: IgnorePointer(
                        ignoring: !_showUI,
                        child: Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            icon: const Icon(Icons.chevron_right_rounded,
                                color: Colors.white, size: 28),
                            tooltip: '下一张',
                            onPressed: _nextPage,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Top action bar (animated overlay)
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

              // Bottom action capsule (animated overlay, pinned to bottom center)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _showUI ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: IgnorePointer(
                      ignoring: !_showUI,
                      child: _buildBottomBar(post),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(Map<String, dynamic> post) {
    final topPadding = MediaQuery.of(context).padding.top;
    final postId = post['id']?.toString() ?? '';
    final site = post['site']?.toString() ?? '';

    return Container(
      padding: EdgeInsets.fromLTRB(12, topPadding + 6, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.68),
            Colors.black.withValues(alpha: 0.25),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // Back button
          Material(
            color: Colors.black38,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 22),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const SizedBox(width: 12),

          // Page counter & Post ID capsule
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_currentIndex + 1} / ${widget.posts.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (site.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 3,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    site,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (postId.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '#$postId',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),

          // Browser open button
          Material(
            color: Colors.black38,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: const Icon(Icons.open_in_browser_rounded,
                  color: Colors.white, size: 20),
              tooltip: '在浏览器中打开',
              onPressed: () {
                final source = post['source'] as String? ?? '';
                final orig = _getOrigUrl(post);
                _openInBrowser(source.isNotEmpty ? source : orig);
              },
            ),
          ),
          const SizedBox(width: 6),

          // Overflow menu
          Material(
            color: Colors.black38,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded,
                  color: Colors.white, size: 20),
              color: const Color(0xFF1E212B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onSelected: (value) {
                switch (value) {
                  case 'copy_image_url':
                    _copyToClipboard(_getOrigUrl(post), '原图链接');
                    break;
                  case 'copy_source':
                    final source = post['source'] as String? ?? '';
                    _copyToClipboard(
                        source.isNotEmpty ? source : _getOrigUrl(post),
                        '来源链接');
                    break;
                  case 'info':
                    _showDetailsModal(post);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'copy_image_url',
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, size: 18, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('复制原图直链', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy_source',
                  child: Row(
                    children: [
                      Icon(Icons.launch_rounded,
                          size: 18, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('复制来源出处', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'info',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('查看详细属性', style: TextStyle(color: Colors.white)),
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

  Widget _buildBottomBar(Map<String, dynamic> post) {
    final postIdStr = post['id']?.toString() ?? '';
    final favNotifier = context.watch<FavoritesNotifier>();
    final isFav = favNotifier.isFavorite(postIdStr);

    final downloadNotifier = context.watch<BaseDownloadNotifier>();
    final isDownloaded =
        downloadNotifier.downloadedItems.any((it) => it.id == postIdStr);

    final isOrigLoaded = _originalLoaded[_currentIndex] == true;
    final isOrigLoading = _originalLoading[_currentIndex] == true;
    final progress = _originalProgress[_currentIndex];
    final hasOrigAvailable = _hasOriginalAvailable(post);

    final fileSizeStr = ViewerFormatUtils.fileSize(
      post['file_size'] as int? ?? 0,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xCC1A1D24),
            borderRadius: BorderRadius.circular(32),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Original quality progressive pill button
              _buildOriginalQualityPill(
                isLoaded: isOrigLoaded,
                isLoading: isOrigLoading,
                progress: progress,
                hasOriginal: hasOrigAvailable,
                fileSizeStr: fileSizeStr,
                onTap: () => _loadOriginal(_currentIndex),
              ),
              const SizedBox(width: 8),

              // Favorite button with heart pulse animation
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(
                    isFav
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFav ? const Color(0xFFFF4B72) : Colors.white70,
                    size: 22,
                  ),
                  tooltip: isFav ? '取消收藏' : '添加收藏',
                  onPressed: () {
                    context.read<FavoritesNotifier>().toggleFavorite(post);
                  },
                ),
              ),

              // Download button
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(
                    isDownloaded
                        ? Icons.check_circle_rounded
                        : Icons.download_rounded,
                    color: isDownloaded
                        ? const Color(0xFF10B981)
                        : Colors.white70,
                    size: 22,
                  ),
                  tooltip: isDownloaded ? '已下载' : '下载原图',
                  onPressed: () async {
                    if (isDownloaded) {
                      _showToast('该图片已在下载相册中');
                    } else {
                      final res = await context
                          .read<BaseDownloadNotifier>()
                          .enqueueDownload(post);
                      switch (res) {
                        case EnqueueResult.success:
                          _showToast('已加入下载队列');
                          break;
                        case EnqueueResult.alreadyDownloaded:
                          _showToast('该图片已存在于相册');
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

              // Post info sheet trigger
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                  tooltip: '图片详情与标签',
                  onPressed: () => _showDetailsModal(post),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOriginalQualityPill({
    required bool isLoaded,
    required bool isLoading,
    required double? progress,
    required bool hasOriginal,
    required String fileSizeStr,
    required VoidCallback onTap,
  }) {
    if (isLoaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 14, color: Color(0xFF10B981)),
            SizedBox(width: 5),
            Text(
              '原图',
              style: TextStyle(
                color: Color(0xFF10B981),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (isLoading) {
      final percentStr =
          progress != null ? '${(progress * 100).toInt()}%' : '载入中';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.blueAccent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2,
                color: Colors.blueAccent,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              percentStr,
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Not loaded yet
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 15, color: Colors.amberAccent),
            const SizedBox(width: 4),
            Text(
              fileSizeStr.isNotEmpty ? '原图 ($fileSizeStr)' : '加载原图',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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

/// Rich metadata, categorized tag chips, and booru post inspector sheet.
class _PostDetailSheet extends StatelessWidget {
  final Map<String, dynamic> post;
  final ValueChanged<String> onTagTap;

  const _PostDetailSheet({
    required this.post,
    required this.onTagTap,
  });

  static Map<String, List<String>> _categorizeTags(Map<String, dynamic> p) {
    final res = <String, List<String>>{
      'artist': [],
      'character': [],
      'copyright': [],
      'general': [],
    };

    void addFromStr(String? raw, String cat) {
      if (raw == null || raw.trim().isEmpty) return;
      for (final t in raw.trim().split(RegExp(r'\s+'))) {
        if (t.isNotEmpty && !res[cat]!.contains(t)) {
          res[cat]!.add(t);
        }
      }
    }

    addFromStr(p['tag_string_artist'] as String?, 'artist');
    addFromStr(p['tag_string_character'] as String?, 'character');
    addFromStr(p['tag_string_copyright'] as String?, 'copyright');
    addFromStr(p['tag_string_general'] as String?, 'general');

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

    final author = (p['author'] as String?)?.trim();
    if (res['artist']!.isEmpty &&
        author != null &&
        author.isNotEmpty &&
        author != 'unknown') {
      res['artist']!.add(author);
    }

    return res;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (ratingLabel, ratingColor) =
        ViewerFormatUtils.parseRating(post['rating'] as String?);

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
    final authorStr = (post['author'] as String? ?? '').trim();
    final postId = post['id']?.toString() ?? '';
    final hasChildren = post['has_children'] == true;

    final tagsMap = _categorizeTags(post);

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
              color: cs.surface.withValues(alpha: 0.92),
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color:
                            cs.onSurfaceVariant.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header row: Post ID & Rating chip
                  Row(
                    children: [
                      Text(
                        '#$postId 详情',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: ratingColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: ratingColor.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          ratingLabel,
                          style: TextStyle(
                            color: ratingColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Key metrics grid cards
                  Row(
                    children: [
                      if (resStr.isNotEmpty)
                        Expanded(
                          child: _buildMetricTile(
                            context,
                            icon: Icons.aspect_ratio_rounded,
                            title: '分辨率',
                            value: resStr,
                          ),
                        ),
                      if (resStr.isNotEmpty && sizeStr.isNotEmpty)
                        const SizedBox(width: 8),
                      if (sizeStr.isNotEmpty)
                        Expanded(
                          child: _buildMetricTile(
                            context,
                            icon: Icons.data_usage_rounded,
                            title: '文件大小',
                            value: extStr.isNotEmpty
                                ? '$sizeStr ($extStr)'
                                : sizeStr,
                          ),
                        ),
                    ],
                  ),
                  if (authorStr.isNotEmpty || timeStr.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (authorStr.isNotEmpty)
                          Expanded(
                            child: _buildMetricTile(
                              context,
                              icon: Icons.person_rounded,
                              title: '上传/作者',
                              value: authorStr,
                            ),
                          ),
                        if (authorStr.isNotEmpty && timeStr.isNotEmpty)
                          const SizedBox(width: 8),
                        if (timeStr.isNotEmpty)
                          Expanded(
                            child: _buildMetricTile(
                              context,
                              icon: Icons.schedule_rounded,
                              title: '发布时间',
                              value: timeStr,
                            ),
                          ),
                      ],
                    ),
                  ],

                  // Has children group posts
                  if (hasChildren) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.collections_bookmark_rounded),
                      label: const Text('查看关联图组 (Group Posts)'),
                      onPressed: () {
                        Navigator.of(context).push(
                          SakuraPageRoute(
                            builder: (_) => GroupPostsScreen(parentPost: post),
                          ),
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Categorized tags
                  _buildTagSection(
                    title: '🎨 创作者 (Artist)',
                    tags: tagsMap['artist']!,
                    chipColor: const Color(0xFFFF5252),
                  ),
                  _buildTagSection(
                    title: '👤 角色 (Character)',
                    tags: tagsMap['character']!,
                    chipColor: const Color(0xFF10B981),
                  ),
                  _buildTagSection(
                    title: '🎬 作品/系列 (Copyright)',
                    tags: tagsMap['copyright']!,
                    chipColor: const Color(0xFF8B5CF6),
                  ),
                  _buildTagSection(
                    title: '🏷️ 标签属性 (General)',
                    tags: tagsMap['general']!,
                    chipColor: const Color(0xFF0284C7),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagSection({
    required String title,
    required List<String> tags,
    required Color chipColor,
  }) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.map((t) {
              return ActionChip(
                label: Text(
                  t,
                  style: TextStyle(
                    fontSize: 12,
                    color: chipColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                backgroundColor: chipColor.withValues(alpha: 0.12),
                side: BorderSide(
                    color: chipColor.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => onTagTap(t),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
