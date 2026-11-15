import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/common/rating_filter_pill.dart';
import 'package:vce1_sakuraview/widgets/common/quick_search_drawer.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_drawer_swipe_region.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';

/// 可复用的分级检索结果网格组件（支持无限分页、图组合并、黑名单过滤、返回不破坏栈）。
class SearchResultsView extends StatefulWidget {
  final String query;
  final String uploader;
  final String artist;
  final String? sort;
  final double bottomPadding;

  const SearchResultsView({
    super.key,
    required this.query,
    this.uploader = '',
    this.artist = '',
    this.sort,
    this.bottomPadding = 24,
  });

  @override
  State<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends State<SearchResultsView> {
  final ScrollController _scrollController = ScrollController();
  final Logger _logger = Logger('SearchResultsView');
  final List<Map<String, dynamic>> _results = [];

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _errorText;
  String? _lastSourceId;
  RatingFilterMode? _lastRatingFilter;

  static const int _perPage = 40;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search(clear: true);
    });
  }

  @override
  void didUpdateWidget(SearchResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query ||
        oldWidget.uploader != widget.uploader ||
        oldWidget.artist != widget.artist ||
        oldWidget.sort != widget.sort) {
      _search(clear: true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _search({bool clear = false}) async {
    final query = widget.query.trim();
    final uploader = widget.uploader.trim();
    final artist = widget.artist.trim();
    if (query.isEmpty && uploader.isEmpty && artist.isEmpty) return;

    if (clear) {
      setState(() {
        _results.clear();
        _currentPage = 1;
        _hasMore = true;
        _errorText = null;
      });
    }
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final siteConfig = Provider.of<SiteConfigProvider>(context, listen: false);
      _lastSourceId = siteConfig.currentSourceId;
      _lastRatingFilter = siteConfig.ratingFilter;
      final apiClient = siteConfig.apiClient;
      final caps = siteConfig.currentSource.capabilities;

      final fetchedPosts = await apiClient.searchPostsWithQuery(
        SourceSearchQuery(
          tags: query,
          uploader: caps.supportsUploaderFilter && uploader.isNotEmpty
              ? uploader
              : null,
          artist: caps.supportsArtistFilter && artist.isNotEmpty ? artist : null,
          page: _currentPage,
          limit: _perPage,
          sort: caps.supportsSort ? widget.sort : null,
          safeMode: siteConfig.safeMode,
          ratingFilter: siteConfig.ratingFilter,
        ),
      );

      if (!mounted) return;
      final blacklist = BlacklistService.instance;
      final ratingFilter = siteConfig.ratingFilter;
      final incomingMaps = fetchedPosts
          .map((p) => p.toApiMap(siteName: siteConfig.currentSourceId))
          .where((item) =>
              !blacklist.isPostBlocked(item) && ratingFilter.matchesPost(item))
          .toList();
      final previousCount = _results.length;
      final merged =
          PostGroupHelper.mergeAndDeduplicate(_results, incomingMaps);

      setState(() {
        if (fetchedPosts.isEmpty) {
          _hasMore = false;
        } else {
          _hasMore = true;
          _results
            ..clear()
            ..addAll(merged);
          _currentPage++;
        }
        _isLoading = false;
        _hasSearched = true;
      });

      if (fetchedPosts.isNotEmpty && merged.length > previousCount) {
        final media = MediaQuery.of(context);
        final isLandscape =
            media.orientation == Orientation.landscape || media.size.width >= 640;
        final gridPreset =
            SettingsProvider.maybeOf(context, listen: false)?.gridSizePreset ??
                GridSizePreset.standard;
        final columns = gridPreset.calcColumns(
          media.size.width,
          isLandscape: isLandscape,
        );
        final tileCacheWidth = computeGridTileCacheWidth(
          context,
          columns: columns,
        );
        final newlyAdded = merged.sublist(previousCount);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            prefetchPostThumbnails(
              context,
              newlyAdded,
              cacheWidth: tileCacheWidth,
            );
          }
        });
      }
    } catch (e) {
      _logger.severe('Search error: $e');
      if (!mounted) return;
      final msg = e.toString().replaceFirst('ApiException: ', '');
      setState(() {
        _isLoading = false;
        _hasSearched = true;
        if (_results.isEmpty) {
          _errorText = msg;
        }
      });
      if (_results.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多失败：$msg')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final siteConfig = context.watch<SiteConfigProvider>();
    if (_lastSourceId != null &&
        (_lastSourceId != siteConfig.currentSourceId ||
            _lastRatingFilter != siteConfig.ratingFilter)) {
      _lastSourceId = siteConfig.currentSourceId;
      _lastRatingFilter = siteConfig.ratingFilter;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(clear: true);
      });
    }

    if (_isLoading && _results.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }

    if (_errorText != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded, size: 52, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _search(clear: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasSearched && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              '未找到匹配的图像作品',
              style: TextStyle(color: Colors.grey[500], fontSize: 15),
            ),
          ],
        ),
      );
    }

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isLandscape =
        media.orientation == Orientation.landscape || width >= 640;
    final gridPreset =
        SettingsProvider.maybeOf(context)?.gridSizePreset ??
            GridSizePreset.standard;
    final columns = gridPreset.calcColumns(width, isLandscape: isLandscape);
    final tileCacheWidth = computeGridTileCacheWidth(
      context,
      columns: columns,
    );

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (_scrollController.hasClients &&
            _scrollController.position.pixels > 160 &&
            _scrollController.position.maxScrollExtent > 0 &&
            _scrollController.position.pixels >=
                _scrollController.position.maxScrollExtent - 800 &&
            _hasMore &&
            !_isLoading) {
          _search();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _search(clear: true),
        child: MasonryGridView.count(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(8, 8, 8, widget.bottomPadding),
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          itemCount: _results.length,
          itemBuilder: (context, index) {
            if (_hasMore &&
                !_isLoading &&
                index >= _results.length - 6 &&
                _scrollController.hasClients &&
                _scrollController.position.pixels > 160) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _search();
              });
            }

            final item = _results[index];
            return SakuraPostCard(
              item: item,
              cacheWidth: tileCacheWidth,
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.push(
                  context,
                  SakuraPageRoute(
                    builder: (_) => PostDetailPage(
                      postData: item,
                      siteName:
                          (item['site_id'] ?? item['site'])?.toString(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 独立推送式搜索结果页：保留完整导航栈与严密逐级返回（结果页 -> 搜索页/上一详情页 -> 主页）。
class SearchResultsPage extends StatelessWidget {
  final String query;
  final String uploader;
  final String artist;
  final String? sort;

  const SearchResultsPage({
    super.key,
    required this.query,
    this.uploader = '',
    this.artist = '',
    this.sort,
  });

  String _buildTitle() {
    final q = query.trim();
    if (q.isNotEmpty) return q;
    final parts = <String>[
      if (artist.trim().isNotEmpty) '画师:${artist.trim()}',
      if (uploader.trim().isNotEmpty) '上传:${uploader.trim()}',
    ];
    return parts.isNotEmpty ? parts.join(' · ') : '搜索结果';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final siteConfig = context.watch<SiteConfigProvider>();
    final recentNotifier = context.watch<RecentTagsNotifier>();
    final isSavedQuick = recentNotifier.hasQuickSearch(
      query: query,
      uploader: uploader,
      artist: artist,
      sort: sort,
    );
    final title = _buildTitle();
    final filterParts = <String>[
      siteConfig.currentSource.name,
      if (query.trim().isNotEmpty && artist.trim().isNotEmpty)
        '画师:${artist.trim()}',
      if (query.trim().isNotEmpty && uploader.trim().isNotEmpty)
        '上传:${uploader.trim()}',
      if (sort != null && sort!.trim().isNotEmpty) '排序:${sort!.trim()}',
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              filterParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          RatingFilterPill(
            mode: siteConfig.ratingFilter,
            onSelected: siteConfig.setRatingFilter,
            padding: const EdgeInsets.only(right: 4),
          ),
          IconButton(
            tooltip: isSavedQuick ? '已加入快速搜索' : '收藏到快速搜索',
            icon: Icon(
              isSavedQuick
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_add_outlined,
              size: 21,
              color: isSavedQuick ? cs.primary : null,
            ),
            onPressed: () async {
              await recentNotifier.toggleQuickSearch(
                query: query,
                uploader: uploader,
                artist: artist,
                sort: sort,
                label: title,
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      endDrawer: const QuickSearchDrawer(),
      endDrawerEnableOpenDragGesture: true,
      body: Builder(
        builder: (innerCtx) => SakuraDrawerSwipeDetector(
          onSwipeLeftFromRight: () => Scaffold.of(innerCtx).openEndDrawer(),
          child: SearchResultsView(
            query: query,
            uploader: uploader,
            artist: artist,
            sort: sort,
          ),
        ),
      ),
    );
  }
}
