import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/domain/models/post.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/services/followed_tags_service.dart';
import 'package:vce1_sakuraview/services/history_service.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_photo_gallery_viewer.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_video_player.dart';
import 'package:vce1_sakuraview/widgets/common/search_results_page.dart';
import 'package:vce1_sakuraview/widgets/common/share_options_sheet.dart';
import 'package:vce1_sakuraview/widgets/common/tag_action_sheet.dart';

/// 作品详情页：严格与「全屏图片浏览器」分离。
///
/// 职责：
/// - 展示 `POST #<id>` 头部、完整未裁切预览图（自适应超长/超宽图，点按进入独立看图器）；
/// - 展示收藏、下载（遵循设置画质）、系统分享动作栏；
/// - 严格按「原作 -> 角色 -> 作者 -> 常规标签」分类展示标签；
/// - 严格区分「上传者 (Uploader)」与「作者 (Artist)」，规范化 Pixiv 等来源链接与未知分级。
class PostDetailPage extends StatefulWidget {
  final Map<String, dynamic> postData;
  final String? siteName;
  final ValueChanged<String>? onTagTap;

  const PostDetailPage({
    super.key,
    required this.postData,
    this.siteName,
    this.onTagTap,
  });

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final ScrollController _scrollController = ScrollController();
  late Map<String, dynamic> _postMap;
  bool _isEnriching = false;
  bool _didAttemptEnrich = false;
  bool _isLoadingGroup = false;
  String? _loadedGroupKey;
  List<Map<String, dynamic>> _groupPosts = const [];
  int _userVote = 0; // 1 = upvoted, -1 = downvoted, 0 = none
  bool _isVoting = false;
  bool _isTogglingFavorite = false;

  @override
  void initState() {
    super.initState();
    _postMap = Map<String, dynamic>.from(widget.postData);
    if ((widget.siteName ?? '').isNotEmpty &&
        (_postMap['site'] == null || _postMap['site'].toString().isEmpty)) {
      _postMap['site'] = widget.siteName;
      _postMap['site_id'] = widget.siteName;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enrichMetadataIfNeeded();
      _loadGroupPostsIfNeeded();
      _loadVoteStateIfSupported();
    });
  }

  Future<void> _loadVoteStateIfSupported() async {
    if (!mounted) return;
    final post = Post.fromMap(_postMap);
    if (post.id <= 0) return;
    try {
      final adapter = context.read<SiteConfigProvider>().adapterFor(_effectiveSiteId);
      if (!adapter.descriptor.capabilities.supportsVoting ||
          !adapter.hasWriteCredentials) {
        return;
      }
      final state = await adapter.fetchPostVoteState('${post.id}');
      if (mounted && state != null) {
        setState(() {
          _userVote = state.userVote;
          if (state.postScore != null) {
            _postMap['score'] = state.postScore;
          }
        });
      }
    } catch (_) {}
  }

  void _showStatusSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? cs.error : null,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _handleVote(int targetVote) async {
    if (_isVoting) return;
    final post = Post.fromMap(_postMap);
    if (post.id <= 0) return;
    final adapter =
        context.read<SiteConfigProvider>().adapterFor(_effectiveSiteId);
    if (!adapter.descriptor.capabilities.supportsVoting) return;

    final prevVote = _userVote;
    final prevScore = _postMap['score'] is int
        ? _postMap['score'] as int
        : int.tryParse(_postMap['score']?.toString() ?? '') ?? post.score;
    final nextVote = (prevVote == targetVote) ? 0 : targetVote;
    final optimisticScore = prevScore - prevVote + nextVote;

    setState(() {
      _isVoting = true;
      _userVote = nextVote;
      _postMap['score'] = optimisticScore;
    });

    try {
      final result = nextVote == 0
          ? await adapter.unvotePost('${post.id}')
          : await adapter.votePost('${post.id}', nextVote);
      if (!mounted) return;
      setState(() {
        _userVote = result?.userVote ?? nextVote;
        if (result?.postScore != null) {
          _postMap['score'] = result!.postScore;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userVote = prevVote;
        _postMap['score'] = prevScore;
      });
      final msg = e.toString().replaceFirst('ApiException: ', '');
      _showStatusSnack(msg, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isVoting = false);
      }
    }
  }

  Future<void> _handleToggleFavorite() async {
    if (_isTogglingFavorite) return;
    setState(() => _isTogglingFavorite = true);
    try {
      final siteProvider = context.read<SiteConfigProvider>();
      final favNotifier = context.read<FavoritesNotifier>();
      final adapter = siteProvider.adapterFor(_effectiveSiteId);
      final res = await favNotifier.toggleFavoriteWithCloudSync(
        _postMap,
        siteName: _effectiveSiteId,
        adapter: adapter,
      );
      if (!mounted) return;
      if (!res.cloudSynced && res.cloudMessage != null) {
        _showStatusSnack(
          res.cloudMessage!,
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTogglingFavorite = false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _hasGroup(Post post) =>
      post.hasChildren ||
      (post.parentId != null && post.parentId! > 0) ||
      (post.poolId != null && post.poolId! > 0) ||
      (_postMap['group_key']?.toString().isNotEmpty ?? false);

  int _effectiveGroupRootId(Post post) {
    final parentId = post.parentId;
    if (parentId != null && parentId > 0) return parentId;
    return post.id;
  }

  String _effectiveGroupCacheKey(Post post) {
    if (post.poolId != null && post.poolId! > 0) {
      return 'pool:${post.poolId}';
    }
    final resolved = PostGroupHelper.resolveGroupKey(_postMap);
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return 'parent:${_effectiveGroupRootId(post)}';
  }

  int _extractPostId(Map<String, dynamic> map) {
    final raw = map['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> _loadGroupPostsIfNeeded({bool force = false}) async {
    if (!mounted) return;
    final currentPost = Post.fromMap(_postMap);
    if (!_hasGroup(currentPost)) return;
    final rootId = _effectiveGroupRootId(currentPost);
    final groupKey = _effectiveGroupCacheKey(currentPost);
    if (rootId <= 0 && (currentPost.poolId ?? 0) <= 0) return;
    if (!force && (_isLoadingGroup || _loadedGroupKey == groupKey)) return;

    setState(() => _isLoadingGroup = true);
    try {
      final siteProvider = context.read<SiteConfigProvider>();
      final adapter = siteProvider.adapterFor(_effectiveSiteId);
      final fetched = await adapter.fetchGroupPosts(_postMap);

      final isOrderedPool = currentPost.poolId != null && currentPost.poolId! > 0;
      final List<Map<String, dynamic>> ordered;

      if (isOrderedPool) {
        final seenIds = <int>{};
        ordered = <Map<String, dynamic>>[];
        for (final item in fetched) {
          final itemId = _extractPostId(item);
          if (itemId <= 0 || !seenIds.add(itemId)) continue;
          ordered.add(Map<String, dynamic>.from(item));
        }
        if (currentPost.id > 0 && !seenIds.contains(currentPost.id)) {
          ordered.insert(0, Map<String, dynamic>.from(_postMap));
        }
      } else {
        final byId = <int, Map<String, dynamic>>{};
        if (currentPost.id > 0) {
          byId[currentPost.id] = Map<String, dynamic>.from(_postMap);
        }
        for (final item in fetched) {
          final itemId = _extractPostId(item);
          if (itemId <= 0) continue;
          byId.putIfAbsent(itemId, () => Map<String, dynamic>.from(item));
        }

        // 若当前查看子帖且父帖搜索未包含主帖本身，补充拉取主帖元数据。
        if (rootId != currentPost.id && !byId.containsKey(rootId)) {
          try {
            final rootDetail = await adapter.getPostDetail(rootId.toString());
            if (rootDetail != null && rootDetail.id > 0) {
              byId[rootDetail.id] =
                  rootDetail.toApiMap(siteName: adapter.sourceId);
            }
          } catch (_) {
            // 主帖补充失败不影响已有子图列表展示
          }
        }

        ordered = <Map<String, dynamic>>[];
        final rootEntry = byId.remove(rootId);
        if (rootEntry != null) {
          ordered.add(rootEntry);
        }
        final remaining = byId.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final entry in remaining) {
          ordered.add(entry.value);
        }
      }

      if (!mounted) return;
      setState(() {
        _loadedGroupKey = groupKey;
        _groupPosts = ordered;
        _isLoadingGroup = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadedGroupKey = groupKey;
        _isLoadingGroup = false;
      });
    }
  }

  String get _effectiveSiteId {
    final s = (_postMap['site_id'] ?? _postMap['site'] ?? widget.siteName ?? '')
        .toString()
        .trim();
    if (s.isNotEmpty) return s.toLowerCase();
    return context.read<SiteConfigProvider>().currentSourceId;
  }

  bool _needsDetailEnrichment(Post post) {
    if (_didAttemptEnrich || post.id <= 0) return false;
    final noCategories = post.artistTags.isEmpty &&
        post.characterTags.isEmpty &&
        post.copyrightTags.isEmpty &&
        post.metaTags.isEmpty;
    final hasRawTags = post.allTags.isNotEmpty ||
        (_postMap['tags']?.toString().trim().isNotEmpty ?? false);
    final missingCategoriesForTaggedPost = noCategories && hasRawTags;
    final zerochanIncomplete = post.effectiveSiteId == 'zerochan' &&
        (post.originalUrl.contains('/600/') ||
            post.originalUrl.isEmpty ||
            post.uploader.isEmpty ||
            noCategories);
    final noUploader = post.uploader.isEmpty;
    if (post.isLocalFile) {
      // 本地已下载条目若缺少分类标签或上传者，仍静默补全在线元数据（不改动本地文件路径）
      return missingCategoriesForTaggedPost || noUploader;
    }
    return zerochanIncomplete ||
        noUploader ||
        missingCategoriesForTaggedPost ||
        post.width <= 0;
  }

  Future<void> _enrichMetadataIfNeeded() async {
    final currentPost = Post.fromMap(_postMap);
    if (!_needsDetailEnrichment(currentPost)) return;
    if (!mounted) return;

    _didAttemptEnrich = true;
    setState(() => _isEnriching = true);
    try {
      final siteProvider = context.read<SiteConfigProvider>();
      final adapter = siteProvider.adapterFor(_effectiveSiteId);
      final detail = await adapter.getPostDetail(currentPost.id.toString());
      if (!mounted || detail == null) return;

      final detailMap = detail.toApiMap(siteName: adapter.sourceId);
      final hasDetailCategories =
          (detailMap['artist_tags'] is List &&
                  (detailMap['artist_tags'] as List).isNotEmpty) ||
              (detailMap['character_tags'] is List &&
                  (detailMap['character_tags'] as List).isNotEmpty) ||
              (detailMap['copyright_tags'] is List &&
                  (detailMap['copyright_tags'] as List).isNotEmpty) ||
              (detailMap['meta_tags'] is List &&
                  (detailMap['meta_tags'] as List).isNotEmpty);

      setState(() {
        final merged = Map<String, dynamic>.from(_postMap);
        for (final entry in detailMap.entries) {
          final val = entry.value;
          if (val == null) continue;
          if (val is String && val.trim().isEmpty) continue;
          if (val is List && val.isEmpty) continue;
          if (val is int && val == 0 && entry.key != 'score') continue;
          // 保留本地已下载文件路径与站点标识
          if (entry.key == 'local_path' ||
              entry.key == 'localPath' ||
              entry.key == 'local_file_path') {
            continue;
          }
          merged[entry.key] = val;
        }
        // 当远端成功返回分类标签时，同步以远端 general_tags 为准，避免已分类标签残留重复出现在常规标签中
        if (hasDetailCategories) {
          final rawGeneral = detailMap['general_tags'];
          merged['general_tags'] =
              rawGeneral is List ? rawGeneral : const <String>[];
        }
        // 确保本地已标记时继续保留
        if (_postMap['is_local_file'] == true) {
          merged['is_local_file'] = true;
          merged['local_path'] = _postMap['local_path'];
          merged['localPath'] = _postMap['localPath'];
          merged['local_file_path'] = _postMap['local_file_path'];
          if (_postMap['downloaded_quality'] != null) {
            merged['downloaded_quality'] = _postMap['downloaded_quality'];
          }
          if (_postMap['is_downloaded_original'] != null) {
            merged['is_downloaded_original'] =
                _postMap['is_downloaded_original'];
          }
        }
        _postMap = merged;
      });
      if (currentPost.isLocalFile) {
        unawaited(
          context
              .read<BaseDownloadNotifier>()
              .updateDownloadedPostMetadata(currentPost.id, _postMap)
              .catchError((_) {}),
        );
      } else {
        unawaited(
          HistoryService.instance.addHistory(_postMap).catchError((_) {}),
        );
      }
    } catch (_) {
      // 详情补充失败时静默降级，保留列表已有元数据
    } finally {
      if (mounted) {
        setState(() => _isEnriching = false);
        _loadGroupPostsIfNeeded();
      }
    }
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '未知';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '未知';
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openUrl(String rawUrl) async {
    final normalized = SourceUrlResolver.normalizeSingleUrl(rawUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法调起外部浏览器')),
        );
      }
    }
  }

  Future<void> _shareCurrentPost(Post post, String postUrl) async {
    final siteName = _resolveSiteDisplayName(post.effectiveSiteId);
    final link = postUrl.isNotEmpty ? postUrl : post.originalUrl;
    final text = SourceUrlResolver.formatShareText(
      postId: post.id,
      canonicalPostUrl: link,
      fallbackUrl: post.originalUrl,
      siteName: siteName,
    );

    await showShareOptionsSheet(
      context: context,
      shareText: text,
      subject: '$siteName POST #${post.id}',
      linkToCopy: link,
      localFilePath: post.localPath,
    );
  }

  Future<void> _downloadSinglePost(Map<String, dynamic> target) async {
    final notifier = context.read<BaseDownloadNotifier>();
    final result = await notifier.enqueueDownload(target);
    if (!mounted) return;
    if (result == EnqueueResult.failed) {
      _showStatusSnack('下载任务创建失败：缺少有效文件地址', isError: true);
    }
  }

  Future<void> _downloadGroupPosts() async {
    if (_groupPosts.isEmpty) return;
    final notifier = context.read<BaseDownloadNotifier>();
    final summary = await notifier.enqueueBatchDownload(_groupPosts);
    if (!mounted) return;
    final text = summary.added > 0
        ? '已加入整组下载队列：新增 ${summary.added} 张'
            '${summary.skippedExisting > 0 ? '，跳过已有/队列中 ${summary.skippedExisting} 张' : ''}'
        : (summary.skippedExisting > 0
            ? '整组 ${summary.total} 张作品均已在本地目录或下载队列中'
            : '当前图组无可下载任务');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _downloadCurrentPost() async {
    if (_groupPosts.length <= 1) {
      await _downloadSinglePost(_postMap);
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('仅下载当前作品'),
              subtitle: Text('POST #${_postMap['id'] ?? ''}'),
              onTap: () => Navigator.pop(ctx, 'single'),
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark_rounded),
              title: Text('下载整组 (${_groupPosts.length} 张)'),
              subtitle: const Text('并发队列下载并保留作者、标签与关联图组信息'),
              onTap: () => Navigator.pop(ctx, 'group'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'group') {
      await _downloadGroupPosts();
    } else if (choice == 'single') {
      await _downloadSinglePost(_postMap);
    }
  }

  void _handleTagSelected(String tag) {
    final clean = tag.trim();
    if (clean.isEmpty) return;
    if (widget.onTagTap != null) {
      Navigator.of(context).pop();
      widget.onTagTap!(clean);
      return;
    }
    Navigator.of(context).push(
      SakuraPageRoute(
        builder: (_) => SearchResultsPage(query: clean),
      ),
    );
  }

  Future<void> _openImageViewer(Post post) async {
    final selectedTag = await Navigator.of(context).push<String>(
      PageRouteBuilder<String>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) {
          return SakuraPhotoGalleryViewer(
            posts: [_postMap],
            initialIndex: 0,
            isLocal: post.isLocalFile,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    if (selectedTag != null && selectedTag.isNotEmpty && mounted) {
      _handleTagSelected(selectedTag);
    }
  }

  String _resolveSiteDisplayName(String siteId) {
    final desc = context.read<SiteConfigProvider>().findSourceById(siteId);
    return desc?.name ?? (siteId.isNotEmpty ? siteId : '未知图源');
  }

  @override
  Widget build(BuildContext context) {
    final post = Post.fromMap(_postMap);
    final siteProvider = context.watch<SiteConfigProvider>();
    final descriptor = siteProvider.findSourceById(post.effectiveSiteId);
    final postUrl = SourceUrlResolver.canonicalPostUrl(
      siteId: post.effectiveSiteId,
      postId: post.id,
      baseUrl: descriptor?.cleanBaseUrl,
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: '返回',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          titleSpacing: 4,
          title: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'POST #${post.id}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  descriptor?.name ?? post.effectiveSiteId,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (_isEnriching)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) async {
                switch (value) {
                  case 'share':
                    await _shareCurrentPost(post, postUrl);
                    break;
                  case 'copy_link':
                    final urlToCopy =
                        postUrl.isNotEmpty ? postUrl : post.originalUrl;
                    await Clipboard.setData(ClipboardData(text: urlToCopy));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制帖子链接')),
                      );
                    }
                    break;
                  case 'browser':
                    final target =
                        postUrl.isNotEmpty ? postUrl : post.originalUrl;
                    await _openUrl(target);
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'share',
                  child: Text('分享当前帖子'),
                ),
                PopupMenuItem(
                  value: 'copy_link',
                  child: Text('复制帖子链接'),
                ),
                PopupMenuItem(
                  value: 'browser',
                  child: Text('在浏览器打开'),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWideLayout = constraints.maxWidth >= 780;
            final caps = descriptor?.capabilities;
            final showVoteStrip = caps?.supportsVoting ?? false;

            if (isWideLayout) {
              final horizontalGap = 20.0;
              final usableWidth =
                  (constraints.maxWidth - 48).clamp(320.0, 1280.0);
              final leftPaneWidth =
                  (usableWidth - horizontalGap) * 0.56;
              final maxRightHeight = constraints.maxHeight;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: SizedBox(
                            height: maxRightHeight - 28,
                            child: SingleChildScrollView(
                              child: _buildPreviewCard(
                                context,
                                post,
                                availableWidthOverride: leftPaneWidth,
                                maxHeightOverride:
                                    (constraints.maxHeight * 0.84)
                                        .clamp(280.0, 820.0),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 5,
                          child: SizedBox(
                            height: maxRightHeight - 28,
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildActionBar(
                                    context,
                                    post,
                                    postUrl,
                                    showVoteStrip: showVoteStrip,
                                  ),
                                  const SizedBox(height: 18),
                                  _buildTagsSection(context, post),
                                  const SizedBox(height: 18),
                                  _buildMetadataSection(
                                    context,
                                    post,
                                    postUrl,
                                    descriptor?.name,
                                  ),
                                  if (_hasGroup(post) ||
                                      _groupPosts.length > 1) ...[
                                    const SizedBox(height: 18),
                                    _buildRelatedGroupSection(context, post),
                                  ],
                                ],
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

            return SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPreviewCard(
                    context,
                    post,
                    availableWidthOverride: constraints.maxWidth - 16,
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildActionBar(
                          context,
                          post,
                          postUrl,
                          showVoteStrip: showVoteStrip,
                        ),
                        const SizedBox(height: 18),
                        _buildTagsSection(context, post),
                        const SizedBox(height: 18),
                        _buildMetadataSection(
                          context,
                          post,
                          postUrl,
                          descriptor?.name,
                        ),
                        if (_hasGroup(post) || _groupPosts.length > 1) ...[
                          const SizedBox(height: 18),
                          _buildRelatedGroupSection(context, post),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPreviewCard(
    BuildContext context,
    Post post, {
    double? availableWidthOverride,
    double? maxHeightOverride,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final hasKnownDims = post.width > 0 && post.height > 0;
    final rawRatio = hasKnownDims ? post.width / post.height : 1.0;

    final maxPreviewHeight =
        maxHeightOverride ?? (screenSize.height * 0.72).clamp(240.0, 720.0);
    final availableWidth =
        (availableWidthOverride ?? (screenSize.width - 16)).clamp(120.0, 2400.0);

    final double displayW;
    final double displayH;
    if (availableWidth / rawRatio <= maxPreviewHeight) {
      displayW = availableWidth;
      displayH = (availableWidth / rawRatio).clamp(140.0, maxPreviewHeight);
    } else {
      displayH = maxPreviewHeight;
      displayW = (maxPreviewHeight * rawRatio).clamp(120.0, availableWidth);
    }

    final viewOriginal =
        SettingsProvider.maybeOf(context)?.viewOriginalByDefault ?? false;
    final localPath = post.localPath;
    final hasLocalFile =
        localPath != null && localPath.isNotEmpty && File(localPath).existsSync();

    if (post.isVideo) {
      final playableSource =
          (hasLocalFile && SourceUrlResolver.isVideoMedia(url: localPath))
              ? localPath
              : post.preferredVideoUrl;
      final videoW = hasKnownDims ? displayW : availableWidth;
      final videoH =
          hasKnownDims ? displayH : (availableWidth * 9 / 16).clamp(180.0, maxPreviewHeight);
      return Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: videoW,
            height: videoH,
            child: SakuraVideoPlayer(
              videoUrl: playableSource,
              posterUrl: post.thumbnailUrl,
              siteId: _effectiveSiteId,
              autoPlay: true,
              looping: true,
              compact: true,
              onEnterFullscreen: () => _openImageViewer(post),
            ),
          ),
        ),
      );
    }

    final shouldPreferAnimatedMaster = post.isAnimatedImage &&
        post.originalUrl.isNotEmpty &&
        !SourceUrlResolver.isAnimatedMedia(url: post.sampleUrl);
    final networkUrl = (viewOriginal || shouldPreferAnimatedMaster) &&
            post.originalUrl.isNotEmpty
        ? post.originalUrl
        : (post.sampleUrl.isNotEmpty ? post.sampleUrl : post.thumbnailUrl);

    Widget previewWidget;
    if (hasLocalFile) {
      previewWidget = Image.file(
        File(localPath),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => SakuraAnimatedImage(
          imageUrl: networkUrl,
          siteId: _effectiveSiteId,
          fit: BoxFit.contain,
        ),
      );
    } else {
      previewWidget = SakuraAnimatedImage(
        imageUrl: networkUrl,
        siteId: _effectiveSiteId,
        fit: BoxFit.contain,
      );
    }

    // 紧贴图片真实纵横比的圆角展示（不留灰边空框），兼顾轻盈投影与点击波纹
    Widget mediaFrame = Stack(
      fit: hasKnownDims ? StackFit.expand : StackFit.passthrough,
      children: [
        previewWidget,
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => _openImageViewer(post),
            ),
          ),
        ),
      ],
    );

    if (hasKnownDims) {
      mediaFrame = SizedBox(
        width: displayW,
        height: displayH,
        child: mediaFrame,
      );
    } else {
      mediaFrame = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: availableWidth,
          maxHeight: maxPreviewHeight,
        ),
        child: mediaFrame,
      );
    }

    return Center(
      child: Hero(
        tag: post.heroTag,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.25),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.28 : 0.08,
                ),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: mediaFrame,
          ),
        ),
      ),
    );
  }

  Widget _buildVoteStrip(BuildContext context, Post post) {
    final cs = Theme.of(context).colorScheme;
    final upActive = _userVote > 0;
    final downActive = _userVote < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _isVoting ? null : () => _handleVote(1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: upActive
                      ? cs.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      upActive
                          ? Icons.thumb_up_rounded
                          : Icons.thumb_up_outlined,
                      size: 17,
                      color: upActive
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      upActive ? '已赞 (+1)' : '点赞 +1',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: upActive
                            ? cs.onPrimaryContainer
                            : cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _isVoting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${post.score}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: upActive
                              ? cs.primary
                              : (downActive ? cs.error : cs.onSurface),
                        ),
                      ),
                      Text(
                        '评分',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _isVoting ? null : () => _handleVote(-1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: downActive
                      ? cs.errorContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      downActive
                          ? Icons.thumb_down_rounded
                          : Icons.thumb_down_outlined,
                      size: 17,
                      color: downActive
                          ? cs.onErrorContainer
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      downActive ? '已踩 (-1)' : '点踩 -1',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: downActive
                            ? cs.onErrorContainer
                            : cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(
    BuildContext context,
    Post post,
    String postUrl, {
    bool showVoteStrip = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final favNotifier = context.watch<FavoritesNotifier>();
    final favKey = post.id > 0 ? '${post.id}' : post.originalUrl;
    final isFav = favNotifier.isFavorite(favKey);
    final postIdStr = post.id > 0 ? '${post.id}' : '';
    BaseDownloadNotifier? downloadNotifier;
    try {
      downloadNotifier = Provider.of<BaseDownloadNotifier>(context, listen: true);
    } on ProviderNotFoundException {
      downloadNotifier = null;
    }
    final isDownloaded = post.isLocalFile ||
        (downloadNotifier != null &&
            DownloadMetadataHelper.findMatchingDownloadedItem(
                  downloadNotifier.downloadedItems,
                  _postMap,
                ) !=
                null);
    final isInQueue = postIdStr.isNotEmpty &&
        (downloadNotifier?.downloadingTasks.any(
              (t) =>
                  (t.postData['id']?.toString() == postIdStr ||
                      t.taskId == postIdStr) &&
                  t.status.isActive,
            ) ??
            false);

    Widget buildBtn({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool active = false,
    }) {
      return Expanded(
        child: FilledButton.tonalIcon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: active
                ? cs.primaryContainer
                : cs.surfaceContainerHighest.withValues(alpha: 0.65),
            foregroundColor:
                active ? cs.onPrimaryContainer : cs.onSurface,
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            buildBtn(
              icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              label: isFav ? '已收藏' : '收藏',
              active: isFav,
              onPressed: _isTogglingFavorite ? null : _handleToggleFavorite,
            ),
            const SizedBox(width: 10),
            buildBtn(
              icon: isDownloaded
                  ? Icons.download_done_rounded
                  : (isInQueue
                      ? Icons.downloading_rounded
                      : Icons.download_outlined),
              label: isDownloaded ? '已下载' : (isInQueue ? '队列中' : '下载'),
              active: isDownloaded || isInQueue,
              onPressed: _downloadCurrentPost,
            ),
            const SizedBox(width: 10),
            buildBtn(
              icon: Icons.share_outlined,
              label: '分享',
              onPressed: () => _shareCurrentPost(post, postUrl),
            ),
          ],
        ),
        if (showVoteStrip) ...[
          const SizedBox(height: 10),
          _buildVoteStrip(context, post),
        ],
      ],
    );
  }

  Widget _buildTagsSection(BuildContext context, Post post) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 严格顺序：原作 -> 角色 -> 作者 -> 常规标签
    final sections = <(String title, List<String> tags, Color chipBg, Color chipFg)>[
      if (post.copyrightTags.isNotEmpty)
        (
          '原作',
          post.copyrightTags,
          cs.secondaryContainer.withValues(alpha: 0.7),
          cs.onSecondaryContainer,
        ),
      if (post.characterTags.isNotEmpty)
        (
          '角色',
          post.characterTags,
          cs.tertiaryContainer.withValues(alpha: 0.7),
          cs.onTertiaryContainer,
        ),
      if (post.artistTags.isNotEmpty)
        (
          '作者',
          post.artistTags,
          cs.primaryContainer.withValues(alpha: 0.75),
          cs.onPrimaryContainer,
        ),
      if (post.generalTags.isNotEmpty || post.metaTags.isNotEmpty)
        (
          '常规标签',
          [...post.generalTags, ...post.metaTags],
          cs.surfaceContainerHighest.withValues(alpha: 0.7),
          cs.onSurface,
        ),
    ];

    if (sections.isEmpty) {
      return Text(
        '暂无标签信息',
        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        FollowedTagsService.instance,
        BlacklistService.instance,
      ]),
      builder: (context, _) {
        final followed = FollowedTagsService.instance;
        final blacklist = BlacklistService.instance;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < sections.length; i++) ...[
              Text(
                sections[i].$1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: sections[i].$2.map((tag) {
                  final isFollowed = followed.isFollowed(tag);
                  final isBlocked = blacklist.isBlocked(tag);
                  return GestureDetector(
                    onLongPress: () => showTagActionSheet(
                      context,
                      tag,
                      onSearchTag: () => _handleTagSelected(tag),
                    ),
                    onSecondaryTap: () => showTagActionSheet(
                      context,
                      tag,
                      onSearchTag: () => _handleTagSelected(tag),
                    ),
                    child: ActionChip(
                      avatar: isBlocked
                          ? Icon(Icons.block_rounded, size: 15, color: cs.error)
                          : (isFollowed
                              ? Icon(Icons.star_rounded,
                                  size: 15, color: cs.primary)
                              : null),
                      label: Text(
                        tag.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isBlocked ? cs.error : sections[i].$4,
                          decoration:
                              isBlocked ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      backgroundColor: sections[i].$3,
                      side: isFollowed
                          ? BorderSide(
                              color: cs.primary.withValues(alpha: 0.45),
                              width: 1,
                            )
                          : BorderSide.none,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 0,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _handleTagSelected(tag),
                    ),
                  );
                }).toList(),
              ),
              if (i < sections.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildMetadataSection(
    BuildContext context,
    Post post,
    String postUrl,
    String? sourceDisplayName,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rating = post.contentRating;
    final normalizedSources = post.normalizedSources;

    Widget row(
      String label,
      String value, {
      VoidCallback? onTap,
      Color? valueColor,
      String? copyText,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 78,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: onTap != null
                  ? GestureDetector(
                      onTap: onTap,
                      child: Text(
                        value,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: valueColor ?? cs.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: valueColor ?? cs.primary,
                        ),
                      ),
                    )
                  : Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: valueColor ?? cs.onSurface,
                      ),
                    ),
            ),
            if (copyText != null && copyText.isNotEmpty)
              IconButton(
                tooltip: '复制$label',
                icon: Icon(
                  Icons.content_copy_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                padding: const EdgeInsets.all(4),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: copyText));
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
        ),
      );
    }

    final adapterCaps =
        context.read<SiteConfigProvider>().adapterFor(post.effectiveSiteId).capabilities;
    final rawAuthorFallback = post.author.trim();
    final safeAuthorFallback = rawAuthorFallback.isNotEmpty &&
            rawAuthorFallback.toLowerCase() != 'unknown' &&
            rawAuthorFallback.toLowerCase() != post.uploader.trim().toLowerCase()
        ? rawAuthorFallback
        : '';
    final artistDisplay = post.artistTags.isNotEmpty
        ? post.artistTags.map((e) => e.replaceAll('_', ' ')).join(', ')
        : (safeAuthorFallback.isNotEmpty
            ? safeAuthorFallback.replaceAll('_', ' ')
            : '未标注');
    final artistSearchToken = post.artistTags.length == 1
        ? post.artistTags.first
        : (post.artistTags.isEmpty && safeAuthorFallback.isNotEmpty
            ? safeAuthorFallback.replaceAll(' ', '_')
            : '');

    final uploaderDisplay = post.uploader.isNotEmpty
        ? post.uploader
        : (post.creatorId != null && post.creatorId! > 0
            ? 'ID #${post.creatorId}'
            : '未知');
    final canFilterUploader =
        post.uploader.isNotEmpty && adapterCaps.supportsUploaderFilter;
    final uploaderQuery = post.uploader.contains(' ')
        ? 'user:"${post.uploader}"'
        : 'user:${post.uploader}';

    return SelectionArea(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '作品信息',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            row('POST ID', '#${post.id}', copyText: '${post.id}'),
            row('图源站点', sourceDisplayName ?? post.effectiveSiteId),
            row(
              '作者',
              artistDisplay,
              onTap: artistSearchToken.isNotEmpty
                  ? () => _handleTagSelected(artistSearchToken)
                  : null,
              copyText: artistDisplay == '未标注' ? null : artistDisplay,
            ),
            row(
              '上传者',
              uploaderDisplay,
              onTap: canFilterUploader
                  ? () => _handleTagSelected(uploaderQuery)
                  : null,
              copyText: uploaderDisplay == '未知' ? null : uploaderDisplay,
            ),
            row('发布时间', _formatDate(post.createdAt)),
            row(
              '尺寸格式',
              '${post.width} × ${post.height} · ${post.fileExt.toUpperCase()} · ${_formatBytes(post.fileSize)}',
            ),
            row(
              '内容分级',
              rating.label,
              valueColor: rating.resolveAccentColor(cs),
            ),
            if (post.score != 0) row('评分热度', '${post.score}'),
            if (postUrl.isNotEmpty)
              row(
                '帖子链接',
                postUrl,
                onTap: () => _openUrl(postUrl),
                copyText: postUrl,
              ),
            for (final srcUrl in normalizedSources)
              row(
                '作品来源',
                srcUrl,
                onTap: srcUrl.startsWith('http') ? () => _openUrl(srcUrl) : null,
                copyText: srcUrl,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedGroupSection(BuildContext context, Post currentPost) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rootId = _effectiveGroupRootId(currentPost);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '关联图组',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                () {
                  final prefix = (currentPost.poolId != null &&
                          currentPost.poolId! > 0)
                      ? (currentPost.poolName.isNotEmpty
                          ? currentPost.poolName
                          : 'Pool #${currentPost.poolId}')
                      : '#$rootId';
                  return _groupPosts.length > 1
                      ? '$prefix · ${_groupPosts.length} 张'
                      : prefix;
                }(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            if (_isLoadingGroup)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_groupPosts.length > 1)
              TextButton.icon(
                onPressed: _downloadGroupPosts,
                icon: const Icon(Icons.download_for_offline_outlined, size: 17),
                label: const Text('下载整组'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoadingGroup && _groupPosts.isEmpty)
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => Container(
                width: 122,
                height: 168,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          )
        else if (_groupPosts.length <= 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(
                  '未获取到其他关联作品',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _loadGroupPostsIfNeeded(force: true),
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 168,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: const {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _groupPosts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) => _buildGroupItemCard(
                  context,
                  _groupPosts[index],
                  currentPost,
                  rootId,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGroupItemCard(
    BuildContext context,
    Map<String, dynamic> itemMap,
    Post currentPost,
    int rootId,
  ) {
    final cs = Theme.of(context).colorScheme;
    final itemPost = Post.fromMap(itemMap);
    final ratio = (itemPost.width > 0 && itemPost.height > 0)
        ? (itemPost.width / itemPost.height).clamp(0.62, 1.45)
        : 0.82;
    final cardWidth = 168.0 * ratio;
    final isCurrent = itemPost.id == currentPost.id;
    final isRootParent = itemPost.id == rootId;
    final siteId = itemPost.effectiveSiteId.isNotEmpty
        ? itemPost.effectiveSiteId
        : _effectiveSiteId;
    final thumbUrl = itemPost.thumbnailUrl.isNotEmpty
        ? itemPost.thumbnailUrl
        : itemPost.sampleUrl;
    final localPath = itemPost.localPath;
    final hasLocal =
        localPath != null && localPath.isNotEmpty && File(localPath).existsSync();

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = (cardWidth * dpr).round().clamp(160, 640);
    final Widget imageWidget = (hasLocal && !itemPost.isVideo)
        ? Image.file(
            File(localPath),
            fit: BoxFit.cover,
            cacheWidth: decodeWidth,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => SakuraAnimatedImage(
              imageUrl: thumbUrl,
              siteId: siteId,
              cacheWidth: decodeWidth,
              fit: BoxFit.cover,
            ),
          )
        : SakuraAnimatedImage(
            imageUrl: thumbUrl,
            siteId: siteId,
            cacheWidth: decodeWidth,
            fit: BoxFit.cover,
          );

    final String? badgeLabel = isCurrent
        ? '当前'
        : (isRootParent ? '主图' : null);

    return SizedBox(
      width: cardWidth,
      height: 168,
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('group_post_${itemPost.id}'),
          onTap: () {
            if (isCurrent) {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                );
              }
              return;
            }
            Navigator.of(context).push(
              SakuraPageRoute(
                builder: (_) => PostDetailPage(
                  postData: itemMap,
                  siteName: (itemMap['site_id'] ??
                          itemMap['site'] ??
                          _effectiveSiteId)
                      .toString(),
                  onTagTap: widget.onTagTap,
                ),
              ),
            );
          },
          child: Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.35),
                width: isCurrent ? 2.2 : 1.0,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(child: imageWidget),
                if (badgeLabel != null)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? cs.primary
                            : cs.surface.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isCurrent ? cs.onPrimary : cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: Tooltip(
                    message: '下载此图',
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _downloadSinglePost(itemMap),
                        child: const Padding(
                          padding: EdgeInsets.all(4.5),
                          child: Icon(
                            Icons.download_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
