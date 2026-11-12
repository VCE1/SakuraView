import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:logging/logging.dart';

import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/widgets/android/android_full_image_screen.dart';
import 'package:vce1_sakuraview/widgets/windows/window_full_image_screen.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_loader.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';

class DownloadedImagesDisplay extends StatefulWidget {
  const DownloadedImagesDisplay({super.key});

  @override
  State<DownloadedImagesDisplay> createState() =>
      _DownloadedImagesDisplayState();
}

class _DownloadedImagesDisplayState extends State<DownloadedImagesDisplay> {
  bool _isFetchingDetails = false;
  final Logger _logger = Logger('DownloadedImagesDisplay');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = Provider.of<BaseDownloadNotifier>(
        context,
        listen: false,
      );
      notifier.setupPhotoManagerListener();
      _refreshData(0);
      _refreshData(1);
    });
  }

  Future<void> _refreshData(int index) async {
    if (!mounted) {
      return;
    }
    final notifier = Provider.of<BaseDownloadNotifier>(context, listen: false);
    if (index == 0) {
      await notifier.scanForDownloadedImages();
    } else {
      await notifier.refreshTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Downloads'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: TabBar(
            onTap: (index) => _refreshData(index),
            tabs: const [
              Tab(text: 'Downloaded'),
              Tab(text: 'Downloading'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_isFetchingDetails)
              const LinearProgressIndicator()
            else
              const SizedBox(height: 4),
            Expanded(
              child: Consumer<BaseDownloadNotifier>(
                builder: (context, downloadNotifier, child) {
                  return TabBarView(
                    children: [
                      _buildCompletedListView(downloadNotifier),
                      _buildDownloadingListView(downloadNotifier),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedListView(BaseDownloadNotifier downloadNotifier) {
    if (downloadNotifier.isLoadingGallery) {
      return const Center(child: SakuraLoader(size: 28));
    }
    final downloadedItems = downloadNotifier.downloadedItems;
    if (downloadedItems.isEmpty) {
      return _buildEmptyState('No downloaded images found.', 0);
    }
    return RefreshIndicator(
      onRefresh: () => _refreshData(0),
      child: ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: downloadedItems.length,
        itemBuilder: (context, index) =>
            _buildGalleryListItem(context, downloadedItems[index]),
      ),
    );
  }

  Widget _buildGalleryListItem(BuildContext context, DownloadedItem item) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          String? filePath;
          if (Platform.isWindows) {
            filePath = item.filePath;
          } else {
            final asset = await AssetEntity.fromId(item.id);
            if (asset == null) {
              _logger.warning('Asset ID not found in media library: ${item.id}. File may have been deleted.');
              if (mounted) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Image file not found. It may have been moved or deleted.')),
                );
              }
              return;
            }
            final file = await asset.originFile;
            filePath = file?.path;
          }

          if (filePath != null && mounted && context.mounted) {
            _logger.info('Opening local image, path: $filePath');
            _navigateToPhotoView(context, filePath, item.id);
          } else {
            _logger.warning('File path is null, cannot view image. Asset ID: ${item.id}');
            if (mounted) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Unable to get file path, cannot view image.')),
              );
            }
          }
        },
        child: SizedBox(
          height: 120,
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Hero(
                  tag: item.id,
                  child: Platform.isWindows
                      ? Image.file(
                          File(item.filePath),
                          fit: BoxFit.cover,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.grey,
                                  size: 40,
                                ),
                              ),
                            );
                          },
                        )
                      : FutureBuilder<Uint8List?>(
                          future: AssetEntity.fromId(item.id).then(
                            (asset) => asset?.thumbnailDataWithSize(
                              const ThumbnailSize(200, 200),
                            ),
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.done &&
                                snapshot.hasData &&
                                snapshot.data != null) {
                              return Image.memory(
                                snapshot.data!,
                                fit: BoxFit.cover,
                                height: double.infinity,
                              );
                            }
                            return Container(color: Colors.grey.shade200);
                          },
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.filename,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (item.width > 0)
                              Text(
                                '${item.width} x ${item.height}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _viewImageDetails(item),
                            child: const Text('Info'),
                          ),
                          TextButton(
                            onPressed: () {
                              Provider.of<BaseDownloadNotifier>(
                                context,
                                listen: false,
                              ).deleteDownloadedItem(item);
                            },
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadingListView(BaseDownloadNotifier downloadNotifier) {
    final tasks = downloadNotifier.downloadingTasks;
    if (tasks.isEmpty) {
      return _buildEmptyState('No download tasks currently.', 1);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => downloadNotifier.pauseAllDownloads(),
                child: const Text('Pause All'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => downloadNotifier.cancelAllDownloads(),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Cancel All'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: tasks.length,
            itemBuilder: (context, index) =>
                _buildDownloadingListItem(context, tasks[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingListItem(BuildContext context, AppDownloadTask task) {
    final downloadNotifier = Provider.of<BaseDownloadNotifier>(
      context,
      listen: false,
    );
    final postData = task.postData;
    String statusText;
    Widget actionButton;

    if (task.status is DownloadTaskStatus) {
      switch (task.status as DownloadTaskStatus) {
        case DownloadTaskStatus.running:
          statusText = 'Downloading ${task.progress}%';
          actionButton = OutlinedButton(
            onPressed: () => downloadNotifier.pauseDownload(task),
            child: const Text('Pause'),
          );
          break;
        case DownloadTaskStatus.paused:
          statusText = 'Paused ${task.progress}%';
          actionButton = OutlinedButton(
            onPressed: () => downloadNotifier.resumeDownload(task),
            child: const Text('Resume'),
          );
          break;
        case DownloadTaskStatus.failed:
          statusText = 'Download Failed';
          actionButton = OutlinedButton(
            onPressed: () => downloadNotifier.retryDownload(task),
            child: const Text('Retry'),
          );
          break;
        default:
          statusText = 'Waiting...';
          actionButton = const OutlinedButton(
            onPressed: null,
            child: Text('Wait'),
          );
      }
    } else {
      statusText = '${task.status} ${task.progress}%';
      actionButton = const SizedBox(width: 70);
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              height: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: CachedNetworkImage(
                  imageUrl: postData['preview_url'] as String? ?? '',
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const Icon(
                    Icons.image_not_supported_outlined,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    postData['tags']?.toString().split(' ').first ??
                        postData['id'].toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    postData['author'] ?? 'Unknown',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (task.progress >= 0)
                    LinearProgressIndicator(
                      value: (task.progress) / 100.0,
                      backgroundColor: Colors.grey.shade300,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    statusText,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(width: 70, child: actionButton),
                const SizedBox(height: 4),
                SizedBox(
                  width: 70,
                  child: OutlinedButton(
                    onPressed: () => downloadNotifier.removeTask(task),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Remove'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPhotoView(
    BuildContext context,
    String imagePath,
    String heroTag,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PhotoViewScreen(imagePath: imagePath, heroTag: heroTag),
      ),
    );
  }

  void _viewImageDetails(DownloadedItem item) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!mounted) return;

    setState(() => _isFetchingDetails = true);

    try {
      String? reliableFilePath;
      if (Platform.isAndroid) {
        final asset = await AssetEntity.fromId(item.id);
        final file = await asset?.originFile;
        if (file == null) {
          throw Exception('Unable to get the real file path. File may be corrupted or removed.');
        }
        reliableFilePath = file.path;
      } else {
        reliableFilePath = item.filePath;
      }

      final postIdString = item.filename.split('.').first;
      final postId = int.tryParse(postIdString);

      if (postId == null) {
        throw Exception('Unable to parse post ID from filename: ${item.filename}');
      }

      final postBox = Hive.box<PostHiveModel>('downloaded_posts');
      final postHiveModel = postBox.get(postId);

      if (postHiveModel == null) {
        throw Exception('Post metadata not found in local database (ID: $postId).');
      }

      final postData = postHiveModel.toApiMap();
      postData['is_local_file'] = true;
      postData['local_file_path'] = reliableFilePath;

      final screen = Platform.isWindows
          ? WindowsFullImageScreen(postData: postData)
          : AndroidFullImageScreen(postData: postData);

      await navigator.push(MaterialPageRoute(builder: (context) => screen));
    } catch (e) {
      _logger.severe('Failed to open detail page: $e');
      messenger.showSnackBar(SnackBar(content: Text('Failed to open details: $e')));
    } finally {
      if (mounted) {
        setState(() => _isFetchingDetails = false);
      }
    }
  }

  Widget _buildEmptyState(String message, int tabIndex) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inbox_outlined, size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            onPressed: () => _refreshData(tabIndex),
          ),
        ],
      ),
    );
  }
}

class PhotoViewScreen extends StatelessWidget {
  final String imagePath;
  final String heroTag;
  const PhotoViewScreen({
    super.key,
    required this.imagePath,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Hero(
        tag: heroTag,
        child: PhotoView(
          imageProvider: FileImage(File(imagePath)),
          minScale: PhotoViewComputedScale.contained * 0.8,
          maxScale: PhotoViewComputedScale.covered * 5.0,
          initialScale: PhotoViewComputedScale.contained,
          backgroundDecoration: const BoxDecoration(color: Colors.transparent),
        ),
      ),
    );
  }
}
