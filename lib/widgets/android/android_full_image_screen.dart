import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:logging/logging.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:vce1_sakuraview/api/yande_api.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';

class FormatUtils {
  static String fileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  static String timeAgo(int ts) {
    if (ts == 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 7) return DateFormat('yyyy/MM/dd').format(date);
    if (diff.inDays > 1) return '${diff.inDays}d ago';
    if (diff.inDays == 1) return '1d ago';
    if (diff.inHours > 1) return '${diff.inHours}h ago';
    if (diff.inHours == 1) return '1h ago';
    if (diff.inMinutes > 1) return '${diff.inMinutes}m ago';
    return 'now';
  }

  static String resolution(num? w, num? h) {
    if (w == null || h == null || w <= 0 || h <= 0) return '';
    return '${w.toInt()} \u00D7 ${h.toInt()}';
  }
}

enum _DisplayMode { preview, loading, zoomable }

class AndroidFullImageScreen extends StatefulWidget {
  final Map<String, dynamic> postData;

  const AndroidFullImageScreen({super.key, required this.postData});

  @override
  State<AndroidFullImageScreen> createState() => _AndroidFullImageScreenState();
}

class _AndroidFullImageScreenState extends State<AndroidFullImageScreen> {
  final Logger _log = Logger('FullImage');
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();

  _DisplayMode _mode = _DisplayMode.preview;
  double? _origProgress;

  List<Map<String, dynamic>> _childPosts = [];
  bool _loadingChildren = false;
  bool _previewLoaded = false;

  String get _id => widget.postData['id']?.toString() ?? '';
  bool get _isLocal => widget.postData['is_local_file'] as bool? ?? false;
  int get _postId => widget.postData['id'] as int? ?? 0;

  String get _previewUrl {
    if (_isLocal) return widget.postData['local_file_path'] as String? ?? '';
    return (widget.postData['sample_url'] ??
            widget.postData['jpeg_url'] ??
            '')
        as String;
  }

  String get _origUrl {
    if (_isLocal) return widget.postData['local_file_path'] as String? ?? '';
    return (widget.postData['file_url'] ?? '') as String;
  }

  @override
  void initState() {
    super.initState();
    _loadPreview();
    if (widget.postData['has_children'] == true && !_isLocal && _postId != 0) {
      _fetchChildren();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _loadPreview() {
    if (_previewUrl.isEmpty) return;
    if (_isLocal) {
      setState(() => _previewLoaded = true);
      return;
    }
    CachedNetworkImageProvider(_previewUrl)
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener(
          (_, __) {
            if (mounted) setState(() => _previewLoaded = true);
          },
          onError: (_, __) {},
        ));
  }

  Future<void> _fetchChildren() async {
    setState(() => _loadingChildren = true);
    try {
      final children = await YandeApi.fetchChildPosts(_postId);
      if (mounted) setState(() => _childPosts = children);
    } catch (e) {
      _log.severe('fetch children: $e');
    } finally {
      if (mounted) setState(() => _loadingChildren = false);
    }
  }

  void _loadOriginal() {
    if (_mode == _DisplayMode.loading) return;
    if (_origUrl.isEmpty) {
      _snack('Original URL not available');
      return;
    }
    setState(() {
      _mode = _DisplayMode.loading;
      _origProgress = 0;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    CachedNetworkImageProvider(_origUrl)
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener(
          (_, __) {
            if (mounted) {
              setState(() {
                _mode = _DisplayMode.zoomable;
                _origProgress = null;
              });
            }
          },
          onChunk: (event) {
            if (mounted &&
                event.expectedTotalBytes != null &&
                event.expectedTotalBytes! > 0) {
              setState(() =>
                  _origProgress = event.cumulativeBytesLoaded / event.expectedTotalBytes!);
            }
          },
          onError: (_, __) => _exitFull('Failed to load original'),
        ));
  }

  void _exitFull([String? msg]) {
    if (!mounted) return;
    setState(() {
      _mode = _DisplayMode.preview;
      _origProgress = null;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (msg != null) _snack(msg);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) _exitFull();
        }
        return KeyEventResult.handled;
      },
      child: switch (_mode) {
        _DisplayMode.loading => _buildLoadingView(),
        _DisplayMode.zoomable => _buildZoomableView(),
        _DisplayMode.preview => _buildDetailView(),
      },
    );
  }

  Widget _buildLoadingView() => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => _exitFull('Cancelled'),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: _origProgress,
                    strokeWidth: 3,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _origProgress != null
                      ? '${(_origProgress! * 100).toStringAsFixed(0)}%'
                      : 'Loading...',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap to cancel',
                  style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildZoomableView() {
    final provider = _isLocal
        ? FileImage(File(_origUrl)) as ImageProvider
        : CachedNetworkImageProvider(_origUrl);
    return Scaffold(
      backgroundColor: Colors.black,
      body: PhotoView(
        imageProvider: provider,
        minScale: PhotoViewComputedScale.contained * 0.9,
        maxScale: PhotoViewComputedScale.covered * 4,
        initialScale: PhotoViewComputedScale.contained,
        heroAttributes: PhotoViewHeroAttributes(tag: _postId.toString()),
        onTapUp: (_, __, ___) => _exitFull(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (_, event) => const Center(
          child: SakuraLoader(size: 28),
        ),
      ),
    );
  }

  Widget _buildDetailView() {
    final p = widget.postData;
    final tags = ((p['tags'] as String?) ?? '').split(' ').where((t) => t.isNotEmpty).toList();
    final author = (p['author'] as String?) ?? '';
    final cid = p['creator_id'] as int? ?? 0;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          _buildImageSliver(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 8),
                _buildHeader(p, tags),
                const SizedBox(height: 12),
                _buildInfoCard(p, author, cid),
                if (_childPosts.isNotEmpty || _loadingChildren) ...[
                  const SizedBox(height: 12),
                  _buildChildrenSection(),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSliver() {
    final w = (widget.postData['sample_width'] as num?)?.toDouble() ?? 0;
    final h = (widget.postData['sample_height'] as num?)?.toDouble() ?? 0;
    final sw = MediaQuery.of(context).size.width;
    final aspect = w > 0 && h > 0 ? w / h : 1.5;
    final imgH = (sw / aspect).clamp(250.0, sw * 1.2).toDouble();

    return SliverAppBar(
      expandedHeight: imgH,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        background: GestureDetector(
          onTap: _loadOriginal,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _isLocal
                  ? Image.file(File(_previewUrl), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox())
                  : CachedNetworkImage(
                      imageUrl: _previewUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (_, __, ___) => const SizedBox(),
                    ),
              Positioned(
                right: 12,
                bottom: 12,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 400),
                  builder: (ctx, v, _) => Opacity(
                    opacity: v,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fullscreen, size: 14, color: Colors.white),
                          SizedBox(width: 4),
                          Text('View original',
                              style: TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!_previewLoaded)
                const Center(child: SakuraLoader(size: 28)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> p, List<String> tags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('ID: ${p['id'] ?? '-'}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            _ActionBtn(
              icon: Icons.favorite_border,
              activeIcon: Icons.favorite,
              isActive: context.watch<FavoritesNotifier>().isFavorite(_id),
              activeColor: Colors.pinkAccent,
              tooltip: 'Favorite',
              onPressed: () =>
                  context.read<FavoritesNotifier>().toggleFavorite(widget.postData),
            ),
            _ActionBtn(
              icon: Icons.download_outlined,
              tooltip: 'Download',
              onPressed: () async {
                final r = await context
                    .read<BaseDownloadNotifier>()
                    .enqueueDownload(widget.postData);
                _snack(switch (r) {
                  EnqueueResult.success => 'Added to download queue',
                  EnqueueResult.alreadyDownloaded => 'Already downloaded',
                  EnqueueResult.alreadyInQueue => 'Already in queue',
                  EnqueueResult.failed => 'Failed to add download',
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags.map((t) => _TagChip(tag: t)).toList(),
          ),
      ],
    );
  }

  Widget _buildInfoCard(Map<String, dynamic> p, String author, int cid) {
    final items = <_InfoItem>[
      if (author.isNotEmpty) _InfoItem('Artist', author, cid: cid),
      if (p['created_at'] != null)
        _InfoItem('Posted', FormatUtils.timeAgo(p['created_at'] as int? ?? 0)),
      if (FormatUtils.resolution(p['width'], p['height']).isNotEmpty)
        _InfoItem('Size', FormatUtils.resolution(p['width'], p['height'])),
      if ((p['file_size'] as int? ?? 0) > 0)
        _InfoItem('File', FormatUtils.fileSize(p['file_size'] as int? ?? 0)),
      if ((p['source'] as String? ?? '').isNotEmpty)
        _InfoItem('Source', p['source'] as String, isLink: true),
      _InfoItem('Rating', ((p['rating'] as String?) ?? '').toUpperCase()),
      if ((p['score'] as int? ?? 0) > 0)
        _InfoItem('Score', '${p['score']}'),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Info', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            ...items.map((i) => _buildInfoRow(i)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(_InfoItem item) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(item.label,
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(150))),
          ),
          Expanded(
            child: item.cid != null
                ? _buildAuthorWidget(item.value, item.cid!)
                : (item.isLink
                    ? InkWell(
                        onTap: () async {
                          final uri = Uri.parse(item.value);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text(item.value,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              decoration: TextDecoration.underline,
                            )),
                      )
                    : Text(item.value, style: const TextStyle(fontSize: 12))),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorWidget(String name, int cid) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final url = Uri.parse('https://yande.re/user/show/$cid');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundImage: CachedNetworkImageProvider(
                'https://yande.re/data/avatars/$cid.jpg'),
            backgroundColor: Colors.grey.shade300,
          ),
          const SizedBox(width: 6),
          Text(name, style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
        ],
      ),
    );
  }

  Widget _buildChildrenSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Variants', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            _loadingChildren
                ? const SizedBox(height: 80,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _childPosts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final cp = _childPosts[i];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    AndroidFullImageScreen(postData: cp),
                              ),
                            ),
                            child: CachedNetworkImage(
                              imageUrl: cp['preview_url'] as String? ?? '',
                              width: 100,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey.shade800,
                                child: const Icon(Icons.broken_image,
                                    color: Colors.white38, size: 28),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  final int? cid;
  final bool isLink;
  const _InfoItem(this.label, this.value, {this.cid, this.isLink = false});
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final bool isActive;
  final Color? activeColor;
  final String tooltip;
  final VoidCallback onPressed;

  const _ActionBtn({
    required this.icon,
    this.activeIcon,
    this.isActive = false,
    this.activeColor,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(isActive && activeIcon != null ? activeIcon! : icon),
      color: isActive ? activeColor : null,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;
  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => Navigator.pop(context, tag),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? c.surfaceContainerHighest : c.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.outlineVariant),
        ),
        child: Text(tag, style: TextStyle(fontSize: 11.5, color: c.onSurfaceVariant)),
      ),
    );
  }
}
