import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/utils/download_settings_page.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_animated_image.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_photo_gallery_viewer.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';

/// 下载管理页面。
///
/// 采用统一的本地作品库视图：
/// - 取消独立「进行中」Tab，仅在存在活跃或失败任务时于顶部内联展示可折叠下载队列条；
/// - 缩略图使用按渲染像素上限约束的 `cacheWidth` 与 `FilterQuality.medium` 消除高分辨率原图摩尔纹；
/// - 支持站点筛选、仅图组筛选、多字段关键词检索与批量多选管理。
class DownloadedImagesDisplay extends StatefulWidget {
  const DownloadedImagesDisplay({super.key});

  @override
  State<DownloadedImagesDisplay> createState() =>
      _DownloadedImagesDisplayState();
}

class _DownloadedImagesDisplayState extends State<DownloadedImagesDisplay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _isGridView = true;
  bool _onlyGroups = false;
  String _selectedSite = '';
  String _searchQuery = '';
  bool _queueExpanded = false;
  bool _isSelecting = false;
  final Set<String> _selectedPaths = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = context.read<BaseDownloadNotifier>();
      notifier.setupPhotoManagerListener();
      notifier.scanForDownloadedImages();
      notifier.refreshTasks();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (_isSelecting) {
      setState(() {
        _isSelecting = false;
        _selectedPaths.clear();
      });
      return;
    }
    _searchFocusNode.unfocus();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  void _openDownloadSettings() {
    _searchFocusNode.unfocus();
    Navigator.of(context).push(
      SakuraPageRoute(builder: (_) => const DownloadSettingsPage()),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }

  String _groupBadgeLabel(DownloadedItem item) {
    if (item.parentId != null && item.parentId! > 0) {
      return '图组 #${item.parentId}';
    }
    if (item.hasChildren && item.id.isNotEmpty) {
      return '图组 #${item.id}';
    }
    return '图组';
  }

  Future<void> _confirmDeleteSelected(
    BaseDownloadNotifier notifier,
    List<DownloadedItem> allItems,
  ) async {
    final targets = allItems
        .where((it) => _selectedPaths.contains(it.filePath))
        .toList();
    if (targets.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除选中作品'),
        content: Text('将从本地目录删除选中的 ${targets.length} 项文件，操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await notifier.deleteDownloadedItems(targets);
      if (!mounted) return;
      setState(() {
        _isSelecting = false;
        _selectedPaths.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 ${targets.length} 项本地文件'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloadNotifier = context.watch<BaseDownloadNotifier>();
    final allItems = downloadNotifier.downloadedItems;
    final visibleQueueTasks = downloadNotifier.downloadingTasks
        .where((t) => t.status.isVisibleInQueue)
        .toList();

    final availableSites = allItems
        .map((e) => (e.siteName ?? '').trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (_selectedSite.isNotEmpty && !availableSites.contains(_selectedSite)) {
      _selectedSite = '';
    }

    final filteredItems = allItems.where((item) {
      if (_selectedSite.isNotEmpty &&
          (item.siteName ?? '').trim().toLowerCase() != _selectedSite) {
        return false;
      }
      return item.matchesSearchQuery(
        _searchQuery,
        onlyGroups: _onlyGroups,
      );
    }).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            tooltip: _isSelecting ? '退出多选' : '返回',
            icon: Icon(
              _isSelecting ? Icons.close_rounded : Icons.arrow_back_rounded,
            ),
            onPressed: _handleBack,
          ),
          title: Text(
            _isSelecting ? '已选 ${_selectedPaths.length} 项' : '下载管理',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          actions: _isSelecting
              ? [
                  IconButton(
                    tooltip: '全选当前',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: () {
                      setState(() {
                        if (_selectedPaths.length == filteredItems.length) {
                          _selectedPaths.clear();
                        } else {
                          _selectedPaths
                            ..clear()
                            ..addAll(filteredItems.map((e) => e.filePath));
                        }
                      });
                    },
                  ),
                  IconButton(
                    tooltip: '删除选中',
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: _selectedPaths.isEmpty
                          ? null
                          : theme.colorScheme.error,
                    ),
                    onPressed: _selectedPaths.isEmpty
                        ? null
                        : () =>
                            _confirmDeleteSelected(downloadNotifier, allItems),
                  ),
                ]
              : [
                  if (allItems.isNotEmpty)
                    IconButton(
                      tooltip: '批量选择',
                      icon: const Icon(Icons.checklist_rounded),
                      onPressed: () => setState(() => _isSelecting = true),
                    ),
                  IconButton(
                    tooltip: _isGridView ? '切换为列表' : '切换为网格',
                    icon: Icon(
                      _isGridView
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded,
                    ),
                    onPressed: () => setState(() => _isGridView = !_isGridView),
                  ),
                  IconButton(
                    tooltip: '下载设置',
                    icon: const Icon(Icons.tune_rounded),
                    onPressed: _openDownloadSettings,
                  ),
                  IconButton(
                    tooltip: '刷新',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () {
                      downloadNotifier.scanForDownloadedImages();
                      downloadNotifier.refreshTasks();
                    },
                  ),
                ],
        ),
        body: Column(
          children: [
            if (visibleQueueTasks.isNotEmpty)
              _buildInlineQueueBanner(
                theme,
                downloadNotifier,
                visibleQueueTasks,
              ),
            if (allItems.isNotEmpty)
              _buildSearchAndFilters(theme, availableSites),
            if (_searchQuery.isNotEmpty ||
                _onlyGroups ||
                _selectedSite.isNotEmpty)
              _buildFilterStatusBar(
                theme,
                filteredItems.length,
                allItems.length,
              ),
            Expanded(
              child: _buildLibraryBody(
                theme,
                downloadNotifier,
                allItems,
                filteredItems,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineQueueBanner(
    ThemeData theme,
    BaseDownloadNotifier notifier,
    List<AppDownloadTask> tasks,
  ) {
    final cs = theme.colorScheme;
    final activeCount = tasks.where((t) => t.status.isActive).length;
    final failedCount =
        tasks.where((t) => t.status == AppDownloadStatus.failed).length;
    final speedLabel = _formatSpeed(notifier.aggregateSpeedBytesPerSec);
    final pct = notifier.aggregateProgressPercent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Material(
        color: cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant.withAlpha(90)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _queueExpanded = !_queueExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: [
                    Icon(
                      failedCount > 0 && activeCount == 0
                          ? Icons.warning_amber_rounded
                          : Icons.downloading_rounded,
                      size: 20,
                      color: failedCount > 0 && activeCount == 0
                          ? cs.error
                          : cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeCount > 0
                                ? '正在下载 $activeCount 项 · $pct%'
                                    '${speedLabel.isNotEmpty ? ' · $speedLabel' : ''}'
                                : '$failedCount 项下载失败',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (activeCount > 0) ...[
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct > 0 ? pct / 100.0 : null,
                                minHeight: 3.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (activeCount > 0)
                      IconButton(
                        tooltip: '全部暂停',
                        icon: const Icon(Icons.pause_rounded, size: 19),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => notifier.pauseAllDownloads(),
                      ),
                    IconButton(
                      tooltip: '清空队列',
                      icon: Icon(
                        Icons.close_rounded,
                        size: 19,
                        color: cs.error,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => notifier.cancelAllDownloads(),
                    ),
                    Icon(
                      _queueExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_queueExpanded) ...[
              const Divider(height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, idx) =>
                      _buildQueueTaskRow(theme, notifier, tasks[idx]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQueueTaskRow(
    ThemeData theme,
    BaseDownloadNotifier notifier,
    AppDownloadTask task,
  ) {
    final cs = theme.colorScheme;
    final previewUrl = (task.postData['preview_url'] ?? '').toString();
    final siteId = (task.postData['site_id'] ?? task.postData['site'])?.toString();
    final speed = task.formattedSpeed;
    final statusLabel = switch (task.status) {
      AppDownloadStatus.running =>
        '${task.progress}%${speed.isNotEmpty ? ' · $speed' : ''}',
      AppDownloadStatus.paused => '已暂停 ${task.progress}%',
      AppDownloadStatus.failed => task.errorMessage?.isNotEmpty == true
          ? '失败：${task.errorMessage}'
          : '下载失败',
      _ => task.status.label,
    };

    Widget actionBtn;
    switch (task.status) {
      case AppDownloadStatus.running:
        actionBtn = IconButton(
          icon: const Icon(Icons.pause_rounded, size: 19),
          tooltip: '暂停',
          onPressed: () => notifier.pauseDownload(task),
        );
        break;
      case AppDownloadStatus.paused:
        actionBtn = IconButton(
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          tooltip: '继续',
          onPressed: () => notifier.resumeDownload(task),
        );
        break;
      case AppDownloadStatus.failed:
        actionBtn = IconButton(
          icon: Icon(Icons.refresh_rounded, size: 19, color: cs.error),
          tooltip: '重试',
          onPressed: () => notifier.retryDownload(task),
        );
        break;
      default:
        actionBtn = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 44,
            height: 44,
            child: previewUrl.isNotEmpty
                ? SakuraAnimatedImage(
                    imageUrl: previewUrl,
                    siteId: siteId,
                    cacheWidth: 140,
                    fit: BoxFit.cover,
                  )
                : Container(
                    color: cs.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined, size: 18),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actionBtn,
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 17),
          tooltip: '移除',
          onPressed: () => notifier.removeTask(task),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters(ThemeData theme, List<String> availableSites) {
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索画师 / 上传者 / 作品 / 标签 / 图组 ID',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withAlpha(110),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('仅图组'),
                selected: _onlyGroups,
                onSelected: (selected) => setState(() => _onlyGroups = selected),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (availableSites.length > 1)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('全部站点', style: TextStyle(fontSize: 12)),
                    selected: _selectedSite.isEmpty,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _selectedSite = ''),
                  ),
                ),
                ...availableSites.map(
                  (site) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(site, style: const TextStyle(fontSize: 12)),
                      selected: _selectedSite == site,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() {
                        _selectedSite = _selectedSite == site ? '' : site;
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFilterStatusBar(ThemeData theme, int matched, int total) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: [
          Text(
            '匹配 $matched / $total 项',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _onlyGroups = false;
                _selectedSite = '';
              });
            },
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('重置筛选'),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryBody(
    ThemeData theme,
    BaseDownloadNotifier notifier,
    List<DownloadedItem> allItems,
    List<DownloadedItem> filteredItems,
  ) {
    if (notifier.isLoadingGallery) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.2));
    }
    if (allItems.isEmpty) {
      return _buildEmptyState(
        icon: Icons.download_outlined,
        title: '暂无已下载图片',
        subtitle: '在作品详情页或图组中点击下载后，文件将保存在您指定的本地目录中。',
        actionLabel: '下载路径与画质设置',
        onAction: _openDownloadSettings,
      );
    }
    if (filteredItems.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        title: '未找到匹配作品',
        subtitle: '可以尝试搜索其他画师名、上传者名、原作标签、站点或图组编号。',
        actionLabel: '清除筛选',
        onAction: () {
          _searchController.clear();
          setState(() {
            _searchQuery = '';
            _onlyGroups = false;
            _selectedSite = '';
          });
        },
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final cols = (width / 150).floor().clamp(2, 6);
    final tileCacheWidth = computeGridTileCacheWidth(context, columns: cols);

    return RefreshIndicator(
      onRefresh: () => notifier.scanForDownloadedImages(),
      child: _isGridView
          ? MasonryGridView.count(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 28),
              crossAxisCount: cols,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              itemCount: filteredItems.length,
              itemBuilder: (context, index) => _buildGridCard(
                filteredItems[index],
                filteredItems,
                tileCacheWidth,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
              itemCount: filteredItems.length,
              itemBuilder: (context, index) => _buildListCard(
                filteredItems[index],
                filteredItems,
              ),
            ),
    );
  }

  Widget _buildLocalThumbnail(
    File file,
    DownloadedItem item,
    ColorScheme cs, {
    int? cacheWidth,
    double iconSize = 28,
  }) {
    if (SourceUrlResolver.isVideoMedia(url: item.filePath)) {
      final ext = item.filePath.split('.').last.toUpperCase();
      return Container(
        color: cs.surfaceContainerHighest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                Icons.play_circle_filled_rounded,
                size: iconSize + 8,
                color: cs.primary,
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(170),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  ext,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: SourceUrlResolver.isAnimatedMedia(url: item.filePath)
          ? null
          : cacheWidth,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => Container(
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.broken_image_outlined, size: iconSize),
        ),
      ),
    );
  }

  Widget _buildGridCard(
    DownloadedItem item,
    List<DownloadedItem> contextList,
    int tileCacheWidth,
  ) {
    final cs = Theme.of(context).colorScheme;
    final file = File(item.filePath);
    final aspectRatio = (item.width > 0 && item.height > 0)
        ? (item.width / item.height).clamp(0.48, 2.1)
        : 0.85;
    final isSelected = _selectedPaths.contains(item.filePath);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? cs.primary : cs.outlineVariant.withAlpha(90),
          width: isSelected ? 2.2 : 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: cs.surfaceContainerLow,
          child: InkWell(
            onTap: () {
              if (_isSelecting) {
                setState(() {
                  if (isSelected) {
                    _selectedPaths.remove(item.filePath);
                  } else {
                    _selectedPaths.add(item.filePath);
                  }
                });
                return;
              }
              _openPostDetail(item);
            },
            onLongPress: () => _showItemActions(item, contextList),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildLocalThumbnail(
                    file,
                    item,
                    cs,
                    cacheWidth: tileCacheWidth,
                  ),
                  if (item.hasGroup)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withAlpha(220),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _groupBadgeLabel(item),
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (_isSelecting)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cs.primary
                              : Colors.black.withAlpha(140),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isSelected
                              ? Icons.check_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: isSelected ? cs.onPrimary : Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListCard(
    DownloadedItem item,
    List<DownloadedItem> contextList,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final file = File(item.filePath);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumbCacheWidth = (72 * dpr).round().clamp(144, 320);

    final sizeLabel = _formatSize(item.fileSizeBytes);
    final dateLabel =
        '${item.creationDate.month}/${item.creationDate.day} '
        '${item.creationDate.hour.toString().padLeft(2, '0')}:'
        '${item.creationDate.minute.toString().padLeft(2, '0')}';

    final artistLabel = item.displayArtist;
    final uploaderLabel = item.uploader ?? '';
    final isSelected = _selectedPaths.contains(item.filePath);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isSelected ? cs.primaryContainer.withAlpha(80) : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outlineVariant.withAlpha(80),
          width: isSelected ? 1.5 : 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (_isSelecting) {
            setState(() {
              if (isSelected) {
                _selectedPaths.remove(item.filePath);
              } else {
                _selectedPaths.add(item.filePath);
              }
            });
            return;
          }
          _openPostDetail(item);
        },
        onLongPress: () => _showItemActions(item, contextList),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: _buildLocalThumbnail(
                    file,
                    item,
                    cs,
                    cacheWidth: thumbCacheWidth,
                    iconSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (item.siteName != null && item.siteName!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.siteName!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            item.id.isNotEmpty ? 'POST #${item.id}' : item.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (item.width > 0) '${item.width}×${item.height}',
                        if (sizeLabel.isNotEmpty) sizeLabel,
                        dateLabel,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (artistLabel.isNotEmpty ||
                        uploaderLabel.isNotEmpty ||
                        item.hasGroup) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (artistLabel.isNotEmpty) '画师: $artistLabel',
                          if (uploaderLabel.isNotEmpty) '上传者: $uploaderLabel',
                          if (item.hasGroup) _groupBadgeLabel(item),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!_isSelecting)
                IconButton(
                  tooltip: '操作',
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => _showItemActions(item, contextList),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPostDetail(DownloadedItem item) {
    _searchFocusNode.unfocus();
    final postData = item.toApiMap();
    Navigator.push(
      context,
      SakuraPageRoute(
        builder: (_) => PostDetailPage(
          postData: postData,
          siteName: item.siteName,
        ),
      ),
    );
  }

  void _openFullscreenViewer(
    DownloadedItem item,
    List<DownloadedItem> contextList,
  ) {
    _searchFocusNode.unfocus();
    final file = File(item.filePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地文件不存在')),
      );
      return;
    }

    final posts = contextList.map((it) => it.toApiMap()).toList();
    final initialIndex = contextList.indexOf(item).clamp(0, posts.length - 1);

    Navigator.push(
      context,
      SakuraPageRoute(
        enableSwipeBack: false,
        builder: (_) => SakuraPhotoGalleryViewer(
          posts: posts,
          initialIndex: initialIndex,
          isLocal: true,
        ),
      ),
    );
  }

  void _showItemActions(
    DownloadedItem item,
    List<DownloadedItem> contextList,
  ) {
    _searchFocusNode.unfocus();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('作品详情'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openPostDetail(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.fullscreen_rounded),
                title: const Text('查看大图'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openFullscreenViewer(item, contextList);
                },
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('批量选择管理'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _isSelecting = true;
                    _selectedPaths.add(item.filePath);
                  });
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '删除本地文件',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<BaseDownloadNotifier>().deleteDownloadedItem(item);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已删除：${item.filename}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withAlpha(150),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 46, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
