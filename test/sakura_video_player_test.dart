import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/domain/models/post.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_video_player.dart';

class _NoopDownloadNotifier extends BaseDownloadNotifier {
  @override
  bool get isLoadingGallery => false;

  @override
  List<DownloadedItem> get downloadedItems => const [];

  @override
  List<AppDownloadTask> get downloadingTasks => const [];

  @override
  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData) async =>
      EnqueueResult.success;

  @override
  Future<void> deleteDownloadedItem(DownloadedItem item) async {}

  @override
  Future<void> scanForDownloadedImages() async {}

  @override
  void setupPhotoManagerListener() {}

  @override
  Future<void> pauseDownload(AppDownloadTask task) async {}

  @override
  Future<void> resumeDownload(AppDownloadTask task) async {}

  @override
  Future<void> cancelDownload(AppDownloadTask task) async {}

  @override
  Future<void> retryDownload(AppDownloadTask task) async {}

  @override
  Future<void> removeTask(AppDownloadTask task) async {}

  @override
  Future<void> pauseAllDownloads() async {}

  @override
  Future<void> cancelAllDownloads() async {}

  @override
  Future<void> refreshTasks() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SakuraVideoPlayer.debugOverridePlatformSupported = null;
  });

  group('Media format classification (MP4, WebM, GIF, WebP)', () {
    test('Identifies video and animated formats accurately including Danbooru zip ugoira', () {
      expect(
        SourceUrlResolver.isVideoMedia(
          url: 'https://cdn.example/sample.webm',
          fileExt: 'webm',
        ),
        isTrue,
      );
      expect(
        SourceUrlResolver.isVideoMedia(
          url: 'https://cdn.example/clip.mp4',
          fileExt: 'mp4',
        ),
        isTrue,
      );
      expect(
        SourceUrlResolver.isAnimatedMedia(
          url: 'https://cdn.example/anim.webp',
          fileExt: 'webp',
        ),
        isTrue,
      );
      expect(
        SourceUrlResolver.isAnimatedMedia(
          url: 'https://cdn.example/anim.gif',
          fileExt: 'gif',
        ),
        isTrue,
      );

      final ugoiraPost = Post.fromMap(const {
        'id': 9527,
        'site': 'danbooru',
        'file_ext': 'zip',
        'file_url': 'https://cdn.donmai.us/original/ugoira.zip',
        'sample_url': 'https://cdn.donmai.us/sample/ugoira_sample.webm',
        'preview_url': 'https://cdn.donmai.us/preview/ugoira.jpg',
        'width': 800,
        'height': 600,
      });

      expect(ugoiraPost.isVideo, isTrue);
      expect(
        ugoiraPost.preferredVideoUrl,
        'https://cdn.donmai.us/sample/ugoira_sample.webm',
      );
    });
  });

  group('SakuraVideoPlayer widget behavior', () {
    testWidgets('PostDetailPage mounts SakuraVideoPlayer for MP4 & WebM posts cleanly', (tester) async {
      final siteProvider = SiteConfigProvider();
      final favNotifier = FavoritesNotifier();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SiteConfigProvider>.value(value: siteProvider),
            ChangeNotifierProvider<FavoritesNotifier>.value(value: favNotifier),
            ChangeNotifierProvider<BaseDownloadNotifier>(
              create: (_) => _NoopDownloadNotifier(),
            ),
          ],
          child: const MaterialApp(
            home: PostDetailPage(
              siteName: 'sakugabooru',
              postData: {
                'id': 3001,
                'site': 'sakugabooru',
                'site_id': 'sakugabooru',
                'file_ext': 'mp4',
                'file_url': 'https://www.sakugabooru.com/data/test_3001.mp4',
                'sample_url': 'https://www.sakugabooru.com/data/test_3001.mp4',
                'preview_url': '',
                'width': 1280,
                'height': 720,
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SakuraVideoPlayer), findsOneWidget);
      expect(find.text('外部播放'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('SakuraVideoPlayer renders graceful fallback for empty or desktop WebM URLs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SakuraVideoPlayer(
              videoUrl: 'https://cdn.donmai.us/original/demo.webm',
              posterUrl: '',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('外部播放'), findsOneWidget);
    });
  });
}
