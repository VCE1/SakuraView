import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:logging/logging.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import 'package:vce1_sakuraview/api/yande_api.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';

class UserUtils {
  static String getAvatarUrl(int creatorId) {
    if (creatorId <= 0) {
      return '';
    }
    return 'https://yande.re/data/avatars/$creatorId.jpg';
  }

  static String getUserPageUrl(int creatorId) =>
      'https://yande.re/user/show/$creatorId';
}

class FormatUtils {
  static String formatFileSize(int fileSize) {
    if (fileSize <= 0) return 'N/A';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String timeAgoSinceDate(int timestamp) {
    if (timestamp == 0) return 'N/A';
    try {
      final DateTime notificationDate =
          DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      final date2 = DateTime.now();
      final difference = date2.difference(notificationDate);
      if (difference.inDays > 8) {
        return DateFormat('yyyy-MM-dd').format(notificationDate);
      }
      if (difference.inDays >= 2) return '${difference.inDays} days ago';
      if (difference.inDays >= 1) return '1 day ago';
      if (difference.inHours >= 2) return '${difference.inHours} hours ago';
      if (difference.inHours >= 1) return '1 hour ago';
      if (difference.inMinutes >= 2) return '${difference.inMinutes} minutes ago';
      if (difference.inMinutes >= 1) return '1 minute ago';
      if (difference.inSeconds >= 3) return '${difference.inSeconds} seconds ago';
      return 'Just now';
    } catch (e) {
      return 'Date error';
    }
  }
}

enum ImageDisplayMode {
  preview,
  loadingOriginal,
  originalZoomable,
}

class WindowsFullImageScreen extends StatefulWidget {
  final Map<String, dynamic> postData;
  final VoidCallback? onNextPageRequested;
  final VoidCallback? onGoToPreviousImage;
  final VoidCallback? onGoToNextImage;
  const WindowsFullImageScreen({
    super.key,
    required this.postData,
    this.onNextPageRequested,
    this.onGoToPreviousImage,
    this.onGoToNextImage,
  });

  @override
  State<WindowsFullImageScreen> createState() => _WindowsFullImageScreenState();
}

class _WindowsFullImageScreenState extends State<WindowsFullImageScreen> {
  String get _currentIdentifier {
    return widget.postData['id']?.toString() ??
        widget.postData['file_url']?.toString() ??
        '';
  }

  static final Logger _logger = Logger('WindowsFullImageScreen');
  ImageDisplayMode _currentMode = ImageDisplayMode.preview;
  bool _originalImageSuccessfullyLoaded = false;
  late PhotoViewController _photoViewController;
  Completer<void>? _originalImageLoadCompleter;

  List<Map<String, dynamic>> _childPosts = [];
  bool _isLoadingChildPosts = false;

  final FocusNode _focusNode = FocusNode();
  double? _originalImageDownloadProgress;

  final ScrollController _scrollController = ScrollController();
  bool _isPreviewImageLoaded = false;

  String get _previewUrl {
    if (_isLocalFile) {
      return widget.postData['local_file_path'] as String? ?? '';
    }
    return widget.postData['sample_url'] as String? ??
        widget.postData['jpeg_url'] as String? ??
        '';
  }

  String get _originalUrl {
    if (_isLocalFile) {
      return widget.postData['local_file_path'] as String? ?? '';
    }
    return widget.postData['file_url'] as String? ?? '';
  }

  bool get _isLocalFile => widget.postData['is_local_file'] as bool? ?? false;
  bool get _hasChildren => widget.postData['has_children'] as bool? ?? false;
  int get _postId => widget.postData['id'] as int? ?? 0;

  @override
  void initState() {
    super.initState();
    _photoViewController = PhotoViewController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
        _logger.info(
            'Focus requested for WindowsFullImageScreen after first frame.');
      }
    });

    if (_isLocalFile) {
      _originalImageSuccessfullyLoaded = true;
      _isPreviewImageLoaded = true;
    } else {
      if (_previewUrl.isNotEmpty) {
        _loadPreviewImage();
      } else {
        _isPreviewImageLoaded = false;
        _logger.warning('Preview URL is empty for post ID: $_postId');
      }
    }

    if (!_isLocalFile && _postId != 0) {
      _resolveFullDetailIfNeeded();
      if (_hasChildren) {
        _fetchChildPosts();
      }
    }
    _scrollController.addListener(_contentScrollListener);
  }

  Future<void> _resolveFullDetailIfNeeded() async {
    final fileUrl = widget.postData['file_url'] as String? ?? '';
    if (!fileUrl.contains('zerochan.net/600/')) return;
    try {
      final apiClient = Provider.of<SiteConfigProvider>(context, listen: false).apiClient;
      final detail = await apiClient.getPostDetail(_postId.toString());
      if (detail != null && mounted) {
        setState(() {
          if (detail.fileUrl != null && detail.fileUrl!.isNotEmpty) {
            widget.postData['file_url'] = detail.fileUrl;
          }
          if (detail.fileSize != null && detail.fileSize! > 0) {
            widget.postData['file_size'] = detail.fileSize;
          }
          if (detail.fileExt != null && detail.fileExt!.isNotEmpty) {
            widget.postData['file_ext'] = detail.fileExt;
          }
        });
      }
    } catch (e) {
      _logger.fine('Detail upgrade skipped: $e');
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _photoViewController.dispose();
    _scrollController.removeListener(_contentScrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPreviewImage() async {
    if (_previewUrl.isEmpty || _isLocalFile) {
      if (mounted) setState(() => _isPreviewImageLoaded = _isLocalFile);
      return;
    }

    _logger
        .info('Attempting to load PREVIEW image for detail view: $_previewUrl');
    final imageProvider = CachedNetworkImageProvider(_previewUrl);
    final ImageStream stream =
        imageProvider.resolve(const ImageConfiguration());
    final Completer<void> imageLoadCompleter = Completer<void>();
    ImageStreamListener? listener;

    listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (listener != null) stream.removeListener(listener);
        if (mounted) {
          setState(() {
            _isPreviewImageLoaded = true;
          });
          _logger.info('PREVIEW image successfully loaded: $_previewUrl');
          _checkScrollAndRequestNextPageIfNeeded();
        }
        if (!imageLoadCompleter.isCompleted) imageLoadCompleter.complete();
      },
      onError: (dynamic exception, StackTrace? stackTrace) {
        if (listener != null) stream.removeListener(listener);
        _logger.severe(
            'Failed to load PREVIEW image: $_previewUrl. Error: $exception');
        if (mounted) {
          setState(() {
            _isPreviewImageLoaded = false;
          });
        }
        if (!imageLoadCompleter.isCompleted) {
          imageLoadCompleter.completeError(exception, stackTrace);
        }
      },
    );
    stream.addListener(listener);
  }

  void _contentScrollListener() {
    _checkScrollAndRequestNextPageIfNeeded();
  }

  void _checkScrollAndRequestNextPageIfNeeded() {
    if (_currentMode == ImageDisplayMode.preview &&
        _isPreviewImageLoaded &&
        widget.onNextPageRequested != null &&
        _scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200.0) {
      _logger.info(
          'Detail content scrolled to bottom AND preview image loaded. Requesting next page from grid.');
      widget.onNextPageRequested!();
    }
  }

  Future<void> _toggleFavorite() async {
    if (_currentIdentifier.isEmpty) {
      _showSnackBar('Cannot favorite: missing valid identifier');
      return;
    }

    final favoritesNotifier =
        Provider.of<FavoritesNotifier>(context, listen: false);

    try {
      await favoritesNotifier.toggleFavorite(widget.postData);

      if (favoritesNotifier.isFavorite(_currentIdentifier)) {
        _showSnackBar('Added to favorites');
      } else {
        _showSnackBar('Removed from favorites');
      }
    } catch (e) {
      _logger.severe('Failed to toggle favorite: $e');
      _showSnackBar('Operation failed: ${e.toString()}');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _fetchChildPosts() async {
    if (!mounted) return;
    setState(() => _isLoadingChildPosts = true);
    try {
      final apiClient = Provider.of<SiteConfigProvider>(context, listen: false).apiClient;
      var children = await apiClient.fetchChildPosts(_postId);
      if (children.isEmpty) {
        children = await YandeApi.fetchChildPosts(_postId);
      }
      if (mounted) {
        setState(() {
          _childPosts = children;
          _isLoadingChildPosts = false;
        });
      }
    } catch (e) {
      _logger.severe('Failed to fetch child posts: $e');
      if (mounted) setState(() => _isLoadingChildPosts = false);
    }
  }

  Future<void> _loadOriginalImageForFullScreen() async {
    if (_isLocalFile) {
      if (mounted) {
        setState(() {
          _originalImageSuccessfullyLoaded = true;
          _currentMode = ImageDisplayMode.originalZoomable;
        });
      }
      return;
    }

    if (_originalUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Original image URL is invalid')));
      }
      return;
    }

    if (_originalImageLoadCompleter != null &&
        !_originalImageLoadCompleter!.isCompleted) {
      _logger.info('Original image loading already in progress...');
      return;
    }
    _originalImageLoadCompleter = Completer<void>();
    _logger.info('Starting full screen original image loading');
    if (mounted) {
      setState(() {
        _currentMode = ImageDisplayMode.loadingOriginal;
        _originalImageDownloadProgress = 0.0;
      });
    }

    try {
      final imageProvider = CachedNetworkImageProvider(_originalUrl);
      final ImageStream stream =
          imageProvider.resolve(const ImageConfiguration());
      final Completer<void> completer = Completer<void>();
      ImageStreamListener? listener;

      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (listener != null) stream.removeListener(listener);
          if (mounted) {
            setState(() {
              _originalImageSuccessfullyLoaded = true;
              _currentMode = ImageDisplayMode.originalZoomable;
              _originalImageDownloadProgress = null;
            });
            _logger.info('Original image loaded successfully');
          }
          if (!completer.isCompleted) completer.complete();
        },
        onChunk: (ImageChunkEvent event) {
          if (mounted &&
              event.expectedTotalBytes != null &&
              event.expectedTotalBytes! > 0) {
            final double progress =
                event.cumulativeBytesLoaded / event.expectedTotalBytes!;
            setState(() => _originalImageDownloadProgress = progress);
          }
        },
        onError: (dynamic exception, StackTrace? stackTrace) {
          if (listener != null) stream.removeListener(listener);
          _logger.severe('Failed to load original image: $exception');
          if (mounted) {
            setState(() {
              _originalImageSuccessfullyLoaded = false;
              _currentMode = ImageDisplayMode.preview;
              _originalImageDownloadProgress = null;
            });
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Failed to load original image, please retry')));
          }
          if (!completer.isCompleted) {
            completer.completeError(exception, stackTrace);
          }
        },
      );
      stream.addListener(listener);
      if (!_originalImageLoadCompleter!.isCompleted) {
        _originalImageLoadCompleter!.complete();
      }
    } catch (e) {
      _logger.severe('Error during original image preloading: $e');
      if (mounted) {
        setState(() {
          _originalImageSuccessfullyLoaded = false;
          _currentMode = ImageDisplayMode.preview;
          _originalImageDownloadProgress = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to load original image, please retry')));
      }
    }
  }

  void _handleImageTapInPreview() {
    if (!mounted) return;
    _logger.info('Preview image tapped, attempting full screen original load...');
    if (_originalImageSuccessfullyLoaded) {
      setState(() {
        _currentMode = ImageDisplayMode.originalZoomable;
      });
    } else {
      _loadOriginalImageForFullScreen();
    }
  }

  void _handleImageTapInFullScreen() {
    if (!mounted) return;
    _logger.info('Full screen mode tapped, exiting full screen');
    setState(() {
      _currentMode = ImageDisplayMode.preview;
      _originalImageDownloadProgress = null;
    });
  }

  void _handleEscKey() {
    if (_currentMode == ImageDisplayMode.originalZoomable ||
        _currentMode == ImageDisplayMode.loadingOriginal) {
      _logger.info('ESC pressed, exiting full screen');
      _handleImageTapInFullScreen();
    } else {
      _logger.info('ESC pressed in preview mode, going back');
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  Widget _buildErrorHolder(String message, {double iconSize = 50}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined,
                size: iconSize, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text(message,
                style: TextStyle(color: Colors.grey[700]),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcons(FavoritesNotifier favoritesNotifier) {
    const double iconButtonSize = 32;
    final bool isFavorited = favoritesNotifier.isFavorite(_currentIdentifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: iconButtonSize,
          height: iconButtonSize,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              isFavorited ? Icons.favorite : Icons.favorite_border,
              color: isFavorited ? Colors.pinkAccent : null,
            ),
            tooltip: isFavorited ? 'Unfavorite' : 'Favorite',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: _toggleFavorite,
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: iconButtonSize,
          height: iconButtonSize,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Add to download queue',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Provider.of<BaseDownloadNotifier>(context, listen: false)
                  .enqueueDownload(widget.postData);
              _showSnackBar('Added post #${widget.postData['id']} to download queue');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value,
      {bool isLink = false, String? urlLink}) {
    TextStyle valueStyle = isLink
        ? TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
            fontSize: 12)
        : const TextStyle(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Expanded(
            child: isLink && urlLink != null && urlLink.isNotEmpty
                ? InkWell(
                    child: Text(value.isNotEmpty ? value : urlLink,
                        style: valueStyle,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 3),
                    onTap: () async {
                      final uri = Uri.parse(urlLink);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Cannot open link: $urlLink')));
                        }
                      }
                    },
                  )
                : Text(value.isNotEmpty ? value : 'N/A',
                    style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildChildPostsSection() {
    if (!_hasChildren || _isLocalFile) return const SizedBox.shrink();
    if (_isLoadingChildPosts) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: Center(child: SakuraLoader(size: 28)));
    }
    if (_childPosts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8.0),
          child: Text('Variants/Child Posts:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _childPosts.length,
            itemBuilder: (context, index) {
              final childPost = _childPosts[index];
              final String childPreviewUrl =
                  childPost['preview_url'] as String? ??
                      childPost['sample_url'] as String? ??
                      '';
              final num pWidth = childPost['preview_width'] as num? ??
                  childPost['sample_width'] as num? ??
                  150;
              final num pHeight = childPost['preview_height'] as num? ??
                  childPost['sample_height'] as num? ??
                  120;
              final double aspect =
                  (pWidth <= 0 || pHeight <= 0) ? 4 / 3 : pWidth / pHeight;

              return AspectRatio(
                aspectRatio: aspect > 0 ? aspect : 4 / 3,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  margin:
                      const EdgeInsets.only(right: 8.0, bottom: 4.0, top: 4.0),
                  elevation: 2,
                  child: InkWell(
                    onTap: () {
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => WindowsFullImageScreen(
                              postData: childPost,
                            ),
                          ),
                        );
                      }
                    },
                    child: childPreviewUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: childPreviewUrl,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            fadeInDuration: const Duration(milliseconds: 200),
                            progressIndicatorBuilder:
                                (context, url, downloadProgress) => Center(
                                    child: CircularProgressIndicator(
                                        value: downloadProgress.progress,
                                        strokeWidth: 2.0)),
                            errorWidget: (context, url, error) => const Center(
                                child: Icon(Icons.broken_image_outlined,
                                    size: 24, color: Colors.grey)),
                          )
                        : _buildErrorHolder('Child preview unavailable', iconSize: 24),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewImage() {
    final post = widget.postData;
    final int imageWidth = post['width'] as int? ?? 0;
    final int imageHeight = post['height'] as int? ?? 0;

    double screenWidth = MediaQuery.of(context).size.width;
    final appBarHeight =
        Scaffold.maybeOf(context)?.appBarMaxHeight ?? kToolbarHeight;
    double availableHeight =
        MediaQuery.of(context).size.height - appBarHeight - 20;
    double imageFrameHeight;

    if (imageWidth > 0 && imageHeight > 0) {
      double imageAspectRatio = imageWidth / imageHeight;
      imageFrameHeight = (screenWidth * 0.95) / imageAspectRatio;
      imageFrameHeight = imageFrameHeight.clamp(150.0, availableHeight * 0.70);
    } else {
      imageFrameHeight = availableHeight * 0.5;
    }

    if (_previewUrl.isEmpty) {
      return SizedBox(
          height: imageFrameHeight,
          child: _buildErrorHolder(_isLocalFile ? 'Local file path invalid' : 'Preview URL missing'));
    }

    return GestureDetector(
      onTap: _handleImageTapInPreview,
      child: Container(
        alignment: Alignment.topCenter,
        constraints: BoxConstraints(
          maxHeight: imageFrameHeight,
          minHeight: 150,
        ),
        child: _isLocalFile
            ? Image.file(
                File(_previewUrl),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    _buildErrorHolder('Local preview load failed'),
              )
            : CachedNetworkImage(
                imageUrl: _previewUrl,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                fadeInDuration: const Duration(milliseconds: 300),
                progressIndicatorBuilder: (context, url, downloadProgress) {
                  return Center(
                      child: CircularProgressIndicator(
                          value: downloadProgress.progress, strokeWidth: 2.0));
                },
                errorWidget: (context, url, error) =>
                    _buildErrorHolder('Preview image load failed'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.postData;

    if (_currentMode == ImageDisplayMode.loadingOriginal) {
      return KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _handleEscKey();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: _handleImageTapInFullScreen,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    value: _originalImageDownloadProgress,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                    backgroundColor: Colors.white.withAlpha(64),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _originalImageDownloadProgress != null &&
                            _originalImageDownloadProgress! >= 0.0
                        ? '${(_originalImageDownloadProgress! * 100).toStringAsFixed(0)}%'
                        : 'Preparing to load...',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tap or press ESC to cancel',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_currentMode == ImageDisplayMode.originalZoomable) {
      ImageProvider imageProvider;
      if (_isLocalFile) {
        imageProvider = FileImage(File(_originalUrl));
      } else {
        imageProvider = CachedNetworkImageProvider(_originalUrl);
      }
      return KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (KeyEvent event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _handleEscKey();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _logger.info('Arrow Left pressed in originalZoomable mode.');
              widget.onGoToPreviousImage?.call();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _logger.info('Arrow Right pressed in originalZoomable mode.');
              widget.onGoToNextImage?.call();
            }
          }
        },
        child: Scaffold(
          backgroundColor: const Color.fromARGB(255, 254, 254, 254),
          body: PhotoView(
            imageProvider: imageProvider,
            filterQuality: FilterQuality.high,
            loadingBuilder: (BuildContext context, ImageChunkEvent? event) {
              if (!_isLocalFile && event != null) {
                return Center(
                    child: CircularProgressIndicator(
                        value: event.cumulativeBytesLoaded /
                            (event.expectedTotalBytes ?? 1),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white)));
              }
              return const SizedBox.shrink();
            },
            errorBuilder: (context, error, stackTrace) {
              Future.microtask(() {
                if (mounted) {
                  setState(() {
                    _originalImageSuccessfullyLoaded = false;
                    _currentMode = ImageDisplayMode.preview;
                  });
                }
              });
              return _buildErrorHolder('Original image display failed');
            },
            minScale: PhotoViewComputedScale.contained * 0.9,
            maxScale: PhotoViewComputedScale.covered * 3.0,
            initialScale: PhotoViewComputedScale.contained,
            heroAttributes: PhotoViewHeroAttributes(
                tag: _postId == 0 ? _originalUrl : _postId.toString()),
            onTapUp: (context, details, controllerValue) =>
                _handleImageTapInFullScreen(),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
        ),
      );
    }

    final tags = (post['tags'] as String? ?? '')
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    final String author = post['author'] as String? ?? 'N/A';
    final int creatorId = post['creator_id'] as int? ?? 0;
    final String source = post['source'] as String? ?? '';
    final int fileSize = post['file_size'] as int? ?? 0;
    final int createdAt = post['created_at'] as int? ?? 0;
    final String rating = (post['rating'] as String? ?? 'N/A').toUpperCase();
    final int score = post['score'] as int? ?? 0;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _handleEscKey();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _logger.info('Arrow Left pressed in preview mode (detail view).');
            widget.onGoToPreviousImage?.call();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _logger.info('Arrow Right pressed in preview mode (detail view).');
            widget.onGoToNextImage?.call();
          }
        }
      },
      child: Consumer<FavoritesNotifier>(
        builder: (context, favoritesNotifier, child) {
          return Scaffold(
            appBar: AppBar(
              title: Text('ID: ${post['id'] ?? 'N/A'}'),
            ),
            body: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPreviewImage(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Tags:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  const SizedBox(height: 4),
                                  if (tags.isNotEmpty)
                                    Wrap(
                                      spacing: 6.0,
                                      runSpacing: 4.0,
                                      children: tags
                                          .map((tag) => ActionChip(
                                                label: Text(tag,
                                                    style: const TextStyle(
                                                        fontSize: 11)),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 5,
                                                        vertical: 1),
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                backgroundColor: Theme.of(
                                                        context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                onPressed: () =>
                                                    Navigator.pop(context, tag),
                                              ))
                                          .toList(),
                                    )
                                  else
                                    const Text('No tags',
                                        style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            fontSize: 11)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Align(
                              alignment: Alignment.topRight,
                              child: _buildActionIcons(favoritesNotifier),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, thickness: 0.5),
                        const SizedBox(height: 10),
                        const Text('Details:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        if (creatorId != 0 && author != 'N/A')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3.0),
                            child: Row(
                              children: [
                                const Text('Artist ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12)),
                                InkWell(
                                  onTap: () async {
                                    final url =
                                        UserUtils.getUserPageUrl(creatorId);
                                    if (await canLaunchUrl(Uri.parse(url))) {
                                      await launchUrl(Uri.parse(url),
                                          mode: LaunchMode.externalApplication);
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: ClipOval(
                                          child: CachedNetworkImage(
                                            imageUrl: UserUtils.getAvatarUrl(
                                                creatorId),
                                            errorWidget:
                                                (context, url, error) =>
                                                    const CircleAvatar(
                                              backgroundColor:
                                                  Colors.transparent,
                                              radius: 10,
                                              child: Icon(Icons.person,
                                                  size: 16, color: Colors.grey),
                                            ),
                                            placeholder: (context, url) =>
                                                Container(
                                                    color:
                                                        Colors.grey.shade300),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(author,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontSize: 12,
                                              decoration:
                                                  TextDecoration.underline)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (author != 'N/A')
                          _buildInfoRow('Author', author),
                        _buildInfoRow(
                            'Posted', FormatUtils.timeAgoSinceDate(createdAt)),
                        if (post['width'] != null && post['height'] != null)
                          _buildInfoRow(
                              'Size', '${post['width']} x ${post['height']}'),
                        if (fileSize > 0)
                          _buildInfoRow(
                              'File Size', FormatUtils.formatFileSize(fileSize)),
                        if (source.isNotEmpty && source != 'N/A')
                          _buildInfoRow('Source', source,
                              isLink: true, urlLink: source),
                        _buildInfoRow('Rating', rating),
                        _buildInfoRow('Score', score.toString()),
                        _buildChildPostsSection(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
