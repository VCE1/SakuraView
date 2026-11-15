import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/pages/site_accounts_page.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';

/// 本地与云端双模式收藏展示组件，供移动端与桌面端共用。
class FavoriteDisplayWidget extends StatefulWidget {
  final double topPadding;
  final double bottomPadding;
  final ValueChanged<String>? onTagTap;

  const FavoriteDisplayWidget({
    super.key,
    this.topPadding = 64.0,
    this.bottomPadding = 80.0,
    this.onTagTap,
  });

  @override
  State<FavoriteDisplayWidget> createState() => _FavoriteDisplayWidgetState();
}

class _FavoriteDisplayWidgetState extends State<FavoriteDisplayWidget> {
  int _favoriteMode = 0; // 0: 本地离线, 1: 云端账号
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _syncCloudToLocal() async {
    final notifier = context.read<FavoritesNotifier>();
    final count = await notifier.syncCloudToLocal();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功将 $count 张云端收藏同步转存至本地离线数据库'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _refreshCloud() {
    final siteConfig = context.read<SiteConfigProvider>();
    context
        .read<FavoritesNotifier>()
        .fetchCloudFavorites(siteConfig, clear: true);
  }

  void _loadMoreCloud() {
    final siteConfig = context.read<SiteConfigProvider>();
    context.read<FavoritesNotifier>().fetchCloudFavorites(siteConfig);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final favNotifier = context.watch<FavoritesNotifier>();
    final siteConfig = context.watch<SiteConfigProvider>();
    final isCloud = _favoriteMode == 1;
    final items = isCloud ? favNotifier.cloudItems : favNotifier.favoriteItems;
    final creds = siteConfig.credentialsForSource(siteConfig.currentSourceId);
    final hasUserOrCookie = creds.isConfigured;

    return Column(
      children: [
        SizedBox(height: widget.topPadding),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: [
                        ButtonSegment<int>(
                          value: 0,
                          label: Text('本地 (${favNotifier.favoriteItems.length})'),
                          icon: const Icon(Icons.offline_pin_outlined, size: 16),
                        ),
                        ButtonSegment<int>(
                          value: 1,
                          label: Text('云端 (${favNotifier.cloudItems.length})'),
                          icon: const Icon(Icons.cloud_outlined, size: 16),
                        ),
                      ],
                      selected: {_favoriteMode},
                      onSelectionChanged: (set) {
                        setState(() => _favoriteMode = set.first);
                        if (set.first == 1 &&
                            !favNotifier.isCloudLoading &&
                            hasUserOrCookie &&
                            (favNotifier.cloudItems.isEmpty ||
                                favNotifier.cloudError != null ||
                                favNotifier.cloudSiteId !=
                                    siteConfig.currentSourceId)) {
                          _refreshCloud();
                        }
                      },
                    ),
                  ),
                  if (isCloud && hasUserOrCookie) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: '同步至本地',
                      icon: const Icon(Icons.sync_alt_rounded, size: 20),
                      onPressed: favNotifier.cloudItems.isNotEmpty
                          ? _syncCloudToLocal
                          : null,
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: '刷新云端收藏',
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: _refreshCloud,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (isCloud && !hasUserOrCookie)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      size: 56,
                      color: cs.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '未配置 ${siteConfig.currentSource.name} 账号',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请先配置用户名或通过内置网页登录获取会话 Cookie，即可直接同步与浏览您的云端收藏夹。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          SakuraPageRoute(
                            builder: (_) => const SiteAccountsPage(),
                          ),
                        ).then((_) {
                          if (mounted) _refreshCloud();
                        });
                      },
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('前往配置或登录账号'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (isCloud && favNotifier.isCloudLoading && items.isEmpty)
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          )
        else if (isCloud && favNotifier.cloudError != null && items.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 52,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '加载云端收藏失败\n${favNotifier.cloudError}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _refreshCloud,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (items.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isCloud
                        ? Icons.cloud_off_rounded
                        : Icons.favorite_outline_rounded,
                    size: 60,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isCloud ? '云端收藏夹为空' : '暂无本地离线收藏',
                    style: TextStyle(color: Colors.grey[500], fontSize: 16),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final availableWidth = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(ctx).width;
                final screenSize = MediaQuery.sizeOf(ctx);
                final isLandscape = screenSize.width >= screenSize.height;
                final gridPreset =
                    SettingsProvider.maybeOf(ctx)?.gridSizePreset ??
                        GridSizePreset.standard;
                final cols = gridPreset.calcColumns(
                  availableWidth,
                  isLandscape: isLandscape,
                );
                final tileCacheWidth =
                    computeGridTileCacheWidth(ctx, columns: cols);

                return NotificationListener<ScrollUpdateNotification>(
                  onNotification: (notification) {
                    if (isCloud &&
                        favNotifier.hasMoreCloud &&
                        !favNotifier.isCloudLoading &&
                        notification.metrics.pixels > 120 &&
                        notification.metrics.extentAfter < 500) {
                      _loadMoreCloud();
                    }
                    return false;
                  },
                  child: Scrollbar(
                    controller: _scrollController,
                    child: MasonryGridView.count(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        10,
                        4,
                        10,
                        widget.bottomPadding,
                      ),
                      crossAxisCount: cols,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final String site = item['site']?.toString() ??
                            item['site_id']?.toString() ??
                            siteConfig.currentSourceId;

                        return SakuraPostCard(
                          item: item,
                          cacheWidth: tileCacheWidth,
                          onTap: () {
                            Navigator.push(
                              context,
                              SakuraPageRoute(
                                builder: (context) => PostDetailPage(
                                  postData: item,
                                  siteName: site,
                                  onTagTap: widget.onTagTap,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
