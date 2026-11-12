import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/utils/download_settings_page.dart';
import 'package:vce1_sakuraview/widgets/android/android_full_image_screen.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';
import 'package:vce1_sakuraview/widgets/windows/window_full_image_screen.dart';

/// Refactored modern Download Management screen referencing Pixes and Boorusama.
class DownloadedImagesDisplay extends StatefulWidget {
  const DownloadedImagesDisplay({super.key});

  @override
  State<DownloadedImagesDisplay> createState() =>
      _DownloadedImagesDisplayState();
}

class _DownloadedImagesDisplayState extends State<DownloadedImagesDisplay>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = context.read<BaseDownloadNotifier>();
      notifier.setupPhotoManagerListener();
      notifier.scanForDownloadedImages();
      notifier.refreshTasks();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openDownloadSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadSettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final downloadNotifier = context.watch<BaseDownloadNotifier>();
    final completedCount = downloadNotifier.downloadedItems.length;
    final activeCount = downloadNotifier.downloadingTasks.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          '下载管理',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: _isGridView ? '切换为列表视图' : '切换为网格视图',
            icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
            onPressed: () {
              setState(() => _isGridView = !_isGridView);
            },
          ),
          IconButton(
            tooltip: '存储目录设置',
            icon: const Icon(Icons.folder_open_rounded),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: cs.onPrimary,
              unselectedLabelColor: cs.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.download_done_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text('已下载 ($completedCount)'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.downloading_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text('下载中 ($activeCount)'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCompletedTab(downloadNotifier),
          _buildDownloadingTab(downloadNotifier),
        ],
      ),
    );
  }

  Widget _buildCompletedTab(BaseDownloadNotifier notifier) {
    if (notifier.isLoadingGallery) {
      return const Center(child: SakuraLoader(size: 32));
    }

    final items = notifier.downloadedItems;
    if (items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cloud_download_outlined,
        title: '暂无已下载图片',
        subtitle: '在画廊中浏览并点击下载按钮，图片将保存在您指定的本地相册中。',
        actionLabel: '前往存储设置',
        onAction: _openDownloadSettings,
      );
    }

    return RefreshIndicator(
      onRefresh: () => notifier.scanForDownloadedImages(),
      child: _isGridView
          ? GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.72,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _buildGridCard(items[index]),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: items.length,
              itemBuilder: (context, index) => _buildListCard(items[index]),
            ),
    );
  }

  Widget _buildGridCard(DownloadedItem item) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final file = File(item.filePath);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openImage(item),
        onLongPress: () => _showItemActions(item),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: cs.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.broken_image_rounded, size: 32),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black87, Colors.transparent],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
                child: Text(
                  item.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListCard(DownloadedItem item) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final file = File(item.filePath);

    String sizeLabel = '';
    if (item.fileSizeBytes > 0) {
      if (item.fileSizeBytes > 1024 * 1024) {
        sizeLabel = '${(item.fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else {
        sizeLabel = '${(item.fileSizeBytes / 1024).toStringAsFixed(0)} KB';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openImage(item),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: cs.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_rounded),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (item.width > 0) '${item.width}×${item.height}',
                        if (sizeLabel.isNotEmpty) sizeLabel,
                        '${item.creationDate.month}/${item.creationDate.day} ${item.creationDate.hour.toString().padLeft(2, '0')}:${item.creationDate.minute.toString().padLeft(2, '0')}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (item.author != null && item.author!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '作者: ${item.author}',
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
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _showItemActions(item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadingTab(BaseDownloadNotifier notifier) {
    final tasks = notifier.downloadingTasks;
    if (tasks.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: '没有正在下载的任务',
        subtitle: '当前下载队列已清空，所有图片均已下载完成。',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text(
                '进行中任务 (${tasks.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => notifier.pauseAllDownloads(),
                icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
                label: const Text('全部暂停'),
              ),
              TextButton.icon(
                onPressed: () => notifier.cancelAllDownloads(),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                label: const Text('全部取消'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            itemCount: tasks.length,
            itemBuilder: (context, index) => _buildDownloadingCard(tasks[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingCard(AppDownloadTask task) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final notifier = context.read<BaseDownloadNotifier>();
    final postData = task.postData;
    final previewUrl = postData['preview_url'] as String? ?? '';

    String statusText = '准备中...';
    Widget actionButton;

    if (task.status is DownloadTaskStatus) {
      final st = task.status as DownloadTaskStatus;
      switch (st) {
        case DownloadTaskStatus.running:
          statusText = '正在下载 ${task.progress}%';
          actionButton = IconButton(
            icon: const Icon(Icons.pause_circle_filled_rounded),
            tooltip: '暂停',
            color: cs.primary,
            onPressed: () => notifier.pauseDownload(task),
          );
          break;
        case DownloadTaskStatus.paused:
          statusText = '已暂停 ${task.progress}%';
          actionButton = IconButton(
            icon: const Icon(Icons.play_circle_filled_rounded),
            tooltip: '恢复',
            color: cs.primary,
            onPressed: () => notifier.resumeDownload(task),
          );
          break;
        case DownloadTaskStatus.failed:
          statusText = '下载失败';
          actionButton = IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重试',
            color: cs.error,
            onPressed: () => notifier.retryDownload(task),
          );
          break;
        default:
          statusText = '排队中 (${task.progress}%)';
          actionButton = const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
      }
    } else {
      statusText = '${task.status} ${task.progress}%';
      actionButton = const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 68,
                height: 68,
                child: previewUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: previewUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: cs.surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_rounded),
                        ),
                      )
                    : Container(
                        color: cs.surfaceContainerHighest,
                        child: const Icon(Icons.image_outlined),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: task.progress > 0 ? task.progress / 100.0 : null,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            actionButton,
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: '取消并移除',
              color: cs.onSurfaceVariant,
              onPressed: () => notifier.removeTask(task),
            ),
          ],
        ),
      ),
    );
  }

  void _openImage(DownloadedItem item) {
    final file = File(item.filePath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件在磁盘上已不存在')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(item.filename, style: const TextStyle(fontSize: 14)),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: () => _viewPostDetails(item),
              ),
            ],
          ),
          body: PhotoView(
            imageProvider: FileImage(file),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 4.0,
            initialScale: PhotoViewComputedScale.contained,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
        ),
      ),
    );
  }

  void _showItemActions(DownloadedItem item) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('查看全图'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openImage(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('查看详细作品信息'),
                onTap: () {
                  Navigator.pop(ctx);
                  _viewPostDetails(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('删除本地文件', style: TextStyle(color: Colors.red)),
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

  void _viewPostDetails(DownloadedItem item) {
    final postId = int.tryParse(item.id);
    if (postId == null) return;
    final postBox = Hive.box<PostHiveModel>('downloaded_posts');
    final hivePost = postBox.get(postId);
    if (hivePost == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到作品原始元数据记录')),
      );
      return;
    }

    final postData = hivePost.toApiMap();
    postData['is_local_file'] = true;
    postData['local_file_path'] = item.filePath;

    final screen = Platform.isWindows
        ? WindowsFullImageScreen(postData: postData)
        : AndroidFullImageScreen(postData: postData);

    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 54, color: cs.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
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
              const SizedBox(height: 20),
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
