import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/pages/android_page.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/pages/search_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/widgets/common/download_images_display_widget.dart';
import 'package:vce1_sakuraview/widgets/common/quick_search_drawer.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_photo_gallery_viewer.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';
import 'package:vce1_sakuraview/widgets/common/search_results_page.dart';

class _FakeDownloadNotifier extends BaseDownloadNotifier {
  final List<DownloadedItem> _items;
  final List<AppDownloadTask> _tasks;
  final List<Map<String, dynamic>> enqueuedPosts = [];

  _FakeDownloadNotifier({
    List<DownloadedItem>? items,
    List<AppDownloadTask>? tasks,
  })  : _items = items ?? [],
        _tasks = tasks ?? [];

  @override
  bool get isLoadingGallery => false;

  @override
  List<DownloadedItem> get downloadedItems => _items;

  @override
  List<AppDownloadTask> get downloadingTasks => _tasks;

  @override
  Future<EnqueueResult> enqueueDownload(Map<String, dynamic> postData) async {
    enqueuedPosts.add(postData);
    return EnqueueResult.success;
  }

  @override
  Future<void> deleteDownloadedItem(DownloadedItem item) async {
    _items.remove(item);
    notifyListeners();
  }

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
  });

  Widget wrapWithProviders(
    Widget child, {
    BaseDownloadNotifier? downloadNotifier,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SiteConfigProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
        ChangeNotifierProvider<BaseDownloadNotifier>(
          create: (_) => downloadNotifier ?? _FakeDownloadNotifier(),
        ),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('PostDetailPage & ImageViewer Separation Widget Tests', () {
    testWidgets(
      'Renders POST header, strict tag section order, separated uploader/artist, normalized Pixiv link, and opens clean viewer without chevrons',
      (tester) async {
        // Pre-write a tiny valid 1x1 PNG synchronously so FakeAsync does not stall on dart:io futures.
        final tempDir = Directory.systemTemp.createTempSync('sakuraview_test_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final sampleFile = File('${tempDir.path}/9001.png');
        sampleFile.writeAsBytesSync(const <int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
          0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
          0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
          0x42, 0x60, 0x82,
        ]);

        final postData = <String, dynamic>{
          'id': 9001,
          'site': 'yandere',
          'site_id': 'yandere',
          'width': 1200,
          'height': 1600,
          'file_ext': 'png',
          'file_size': 2097152,
          'rating': 'unknown',
          'uploader': 'upload_user_99',
          'author': 'real_artist_x',
          'copyright_tags': ['original_work'],
          'character_tags': ['heroine_a'],
          'artist_tags': ['real_artist_x'],
          'general_tags': ['blue_sky'],
          'source': 'https://i.pximg.net/img-original/img/2026/05/01/152004614_p0.jpg',
          'is_local_file': true,
          'local_file_path': sampleFile.path,
          'file_url': sampleFile.path,
          'sample_url': sampleFile.path,
          'preview_url': sampleFile.path,
        };

        await tester.pumpWidget(
          wrapWithProviders(
            PostDetailPage(postData: postData, siteName: 'yandere'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('POST #9001'), findsOneWidget);
        expect(find.text('收藏'), findsOneWidget);
        expect(find.text('已下载'), findsOneWidget);
        expect(find.text('分享'), findsOneWidget);

        // Verify strict tag section ordering: 原作 -> 角色 -> 作者 -> 常规标签
        final copyrightY = tester.getTopLeft(find.text('原作')).dy;
        final characterY = tester.getTopLeft(find.text('角色')).dy;
        final artistY = tester.getTopLeft(find.text('作者').first).dy;
        final generalY = tester.getTopLeft(find.text('常规标签')).dy;
        expect(copyrightY < characterY, isTrue);
        expect(characterY < artistY, isTrue);
        expect(artistY < generalY, isTrue);

        // Verify separated uploader vs artist & normalized Pixiv source & unknown rating
        expect(find.text('upload_user_99'), findsOneWidget);
        expect(find.text('未知'), findsWidgets);
        expect(
          find.text('https://www.pixiv.net/artworks/152004614'),
          findsOneWidget,
        );

        // 3-dot menu has '分享当前帖子'
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();
        expect(find.text('分享当前帖子'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Tapping preview navigates to SakuraPhotoGalleryViewer with NO chevrons.
        // Pump route transition duration rather than pumpAndSettle because PhotoView
        // renders an indeterminate CircularProgressIndicator while FileImage decodes.
        await tester.tap(find.byType(Hero).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(SakuraPhotoGalleryViewer), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
        expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

        // Unhandled keys must NOT be swallowed by Focus (returning false = KeyEventResult.ignored).
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.space), isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byType(SakuraPhotoGalleryViewer), findsNothing);
        expect(find.byType(PostDetailPage), findsOneWidget);
      },
    );

    testWidgets(
      'Clicking 上传者 and 作者 metadata rows triggers search callbacks & creatorId fallback displays cleanly',
      (tester) async {
        final capturedQueries = <String>[];
        final testPost = <String, dynamic>{
          'id': 9101,
          'site': 'yandere',
          'site_id': 'yandere',
          'width': 800,
          'height': 1000,
          'file_ext': 'png',
          'rating': 'safe',
          'uploader': 'upload_user_99',
          'author': 'real_artist_x',
          'artist_tags': ['real_artist_x'],
          'tags': 'real_artist_x solo',
          'is_local_file': true,
          'local_file_path': '',
          'file_url': '',
          'sample_url': '',
          'preview_url': '',
        };

        await tester.pumpWidget(
          wrapWithProviders(
            Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => PostDetailPage(
                            siteName: 'yandere',
                            postData: testPost,
                            onTagTap: capturedQueries.add,
                          ),
                        ),
                      );
                    },
                    child: const Text('OpenDetail'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Open detail & tap 上传者 row
        await tester.tap(find.text('OpenDetail'));
        await tester.pumpAndSettle();
        final uploaderFinder = find.text('upload_user_99');
        await tester.ensureVisible(uploaderFinder);
        await tester.pumpAndSettle();
        await tester.tap(uploaderFinder);
        await tester.pumpAndSettle();
        expect(capturedQueries, contains('user:upload_user_99'));

        // 2. Open detail & tap 作者 metadata row
        await tester.tap(find.text('OpenDetail'));
        await tester.pumpAndSettle();
        final artistFinder = find.text('real artist x').last;
        await tester.ensureVisible(artistFinder);
        await tester.pumpAndSettle();
        await tester.tap(artistFinder);
        await tester.pumpAndSettle();
        expect(capturedQueries, contains('real_artist_x'));

        // Missing uploader with creator_id shows ID #4242 rather than blank
        await tester.pumpWidget(
          wrapWithProviders(
            PostDetailPage(
              siteName: 'danbooru',
              postData: <String, dynamic>{
                'id': 9102,
                'site': 'danbooru',
                'site_id': 'danbooru',
                'width': 800,
                'height': 1000,
                'file_ext': 'png',
                'rating': 'general',
                'creator_id': 4242,
                'uploader': '',
                'author': '',
                'tags': 'solo',
                'is_local_file': true,
                'file_url': '',
                'sample_url': '',
                'preview_url': '',
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('ID #4242'), findsOneWidget);
      },
    );

    testWidgets(
      'Renders related image group horizontally at bottom and clicking sibling opens PostDetailPage',
      (tester) async {
        final fakeSiteProvider = _FakeSiteConfigProvider();
        final currentPost = <String, dynamic>{
          'id': 9001,
          'parent_id': 9000,
          'has_children': false,
          'site': 'yandere',
          'site_id': 'yandere',
          'width': 1000,
          'height': 1400,
          'file_ext': 'jpg',
          'rating': 'safe',
          'tags': 'test_group',
          'preview_url': '',
          'sample_url': '',
          'file_url': '',
        };

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SiteConfigProvider>.value(
                value: fakeSiteProvider,
              ),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>(
                create: (_) => _FakeDownloadNotifier(),
              ),
            ],
            child: MaterialApp(
              home: PostDetailPage(
                postData: currentPost,
                siteName: 'yandere',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('关联图组'), findsOneWidget);
        expect(find.text('#9000 · 8 张'), findsOneWidget);
        expect(find.text('主图'), findsOneWidget);
        expect(find.text('当前'), findsOneWidget);

        final metaY = tester.getTopLeft(find.text('作品信息')).dy;
        final groupHeaderY = tester.getTopLeft(find.text('关联图组')).dy;
        expect(groupHeaderY > metaY, isTrue);

        // Verify horizontal ListView exists, scroll detail view down to it, then verify horizontal scroll & sibling tap
        final horizontalList = find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        );
        expect(horizontalList, findsOneWidget);
        await tester.ensureVisible(horizontalList);
        await tester.pumpAndSettle();

        final horizontalScrollable = find.descendant(
          of: horizontalList,
          matching: find.byType(Scrollable),
        );
        expect(
          tester.state<ScrollableState>(horizontalScrollable).position.pixels,
          0.0,
        );
        await tester.drag(horizontalList, const Offset(-180, 0));
        await tester.pumpAndSettle();
        expect(
          tester.state<ScrollableState>(horizontalScrollable).position.pixels,
          greaterThan(0.0),
        );

        // Tapping a well-centered non-current sibling opens another PostDetailPage cleanly
        final targetSibling = find.byKey(const ValueKey<String>('group_post_9003'));
        await tester.ensureVisible(targetSibling);
        await tester.pumpAndSettle();
        await tester.tap(targetSibling);
        await tester.pumpAndSettle();

        expect(find.byType(PostDetailPage), findsOneWidget);
        expect(find.text('POST #9001'), findsNothing);
        expect(find.text('POST #9003'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('DownloadedImagesDisplay Search & Navigation Loop Tests', () {
    testWidgets(
      'Supports search by artist/uploader/group and Back button returns cleanly',
      (tester) async {
        final fakeNotifier = _FakeDownloadNotifier(
          items: [
            DownloadedItem(
              id: '101',
              filePath: '/nonexistent/101.png',
              filename: '101.png',
              creationDate: DateTime(2026, 5, 1),
              author: 'alice_artist',
              uploader: 'bob_uploader',
              siteName: 'konachan',
              artistTags: const ['alice_artist'],
              copyrightTags: const ['touhou'],
              parentId: 100,
            ),
            DownloadedItem(
              id: '202',
              filePath: '/nonexistent/202.png',
              filename: '202.png',
              creationDate: DateTime(2026, 5, 2),
              author: 'charlie_artist',
              uploader: 'dave_uploader',
              siteName: 'yandere',
              artistTags: const ['charlie_artist'],
              copyrightTags: const ['original'],
            ),
          ],
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SiteConfigProvider()),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>.value(
                value: fakeNotifier,
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => const DownloadedImagesDisplay(),
                          ),
                        );
                      },
                      child: const Text('打开下载管理'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('打开下载管理'));
        await tester.pumpAndSettle();
        expect(find.text('下载管理'), findsOneWidget);
        expect(find.byType(TabBar), findsNothing);
        expect(find.textContaining('进行中'), findsNothing);
        expect(find.text('POST #101'), findsNothing); // grid uses crisp border/aspect cards without text clutter

        // Search by group parentId shows only item 101
        await tester.enterText(find.byType(TextField), '100');
        await tester.pumpAndSettle();
        expect(find.text('匹配 1 / 2 项'), findsOneWidget);

        // Search by second item's artist matches item 202
        await tester.enterText(find.byType(TextField), 'charlie_artist');
        await tester.pumpAndSettle();
        expect(find.text('匹配 1 / 2 项'), findsOneWidget);

        // Back button returns cleanly to launcher page
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.text('打开下载管理'), findsOneWidget);
      },
    );

    testWidgets(
      'Shows inline collapsible progress banner ONLY when active/failed tasks exist',
      (tester) async {
        final fakeNotifier = _FakeDownloadNotifier(
          tasks: [
            AppDownloadTask(
              taskId: 't_1',
              filename: '991.png',
              url: 'https://example.com/991.png',
              status: AppDownloadStatus.running,
              progress: 45,
              speedBytesPerSec: 512 * 1024,
              postData: const {'id': 991},
              savedDir: '/tmp',
            ),
          ],
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SiteConfigProvider()),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>.value(
                value: fakeNotifier,
              ),
            ],
            child: const MaterialApp(home: DownloadedImagesDisplay()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TabBar), findsNothing);
        expect(find.textContaining('正在下载 1 项'), findsOneWidget);
      },
    );
  });

  group('Drawer Navigation Closure & Pagination Anti-Cascade Regression Tests', () {
    testWidgets(
      'Every Drawer item opens cleanly without disposing root AndroidImageGridPage and returns without black screen',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeSite = _FakeSiteConfigProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SiteConfigProvider>.value(value: fakeSite),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>(
                create: (_) => _FakeDownloadNotifier(),
              ),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => RecentTagsNotifier()),
            ],
            child: MaterialApp(
              home: const AndroidImageGridPage(),
              routes: {
                '/downloads': (_) => const DownloadedImagesDisplay(),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AndroidImageGridPage), findsOneWidget);
        // Initial load fetches only page 1 (never auto-cascades page 2/3 on wide tablet screen)
        expect(fakeSite.fakeAdapter.requestedPages, equals([1]));

        Future<void> openDrawer() async {
          await tester.tap(find.byTooltip('导航菜单'));
          await tester.pumpAndSettle();
        }

        // 1. Drawer -> 发现 (must switch tab cleanly, NEVER pop root route!)
        await openDrawer();
        await tester.tap(find.text('发现').last);
        await tester.pumpAndSettle();
        expect(find.byType(AndroidImageGridPage), findsOneWidget);

        // 2. Drawer -> 搜索
        await openDrawer();
        await tester.tap(find.text('搜索').last);
        await tester.pumpAndSettle();
        expect(find.byType(AndroidImageGridPage), findsOneWidget);
        expect(find.byType(SearchPage), findsOneWidget);

        // 3. Drawer -> 收藏 (must NOT pop root route!)
        await openDrawer();
        await tester.tap(find.text('收藏').last);
        await tester.pumpAndSettle();
        expect(find.byType(AndroidImageGridPage), findsOneWidget);
        expect(find.text('我的收藏'), findsOneWidget);

        // 4-9. Pushed Drawer routes: must push cleanly with canPop==true & return to live root
        final pushedRoutes = <(String, Finder)>[
          ('下载', find.text('下载管理')),
          ('历史', find.text('浏览历史')),
          ('黑名单', find.text('黑名单').first),
          ('账号', find.text('站点账号')),
          ('设置', find.text('设置').first),
          ('关于', find.text('感谢使用 SakuraView，请多多指教~')),
        ];

        for (final entry in pushedRoutes) {
          await openDrawer();
          await tester.tap(find.text(entry.$1).last);
          await tester.pumpAndSettle();
          expect(entry.$2, findsOneWidget, reason: '${entry.$1} failed to render');
          await tester.tap(find.byTooltip('返回'));
          await tester.pumpAndSettle();
          expect(
            find.byType(AndroidImageGridPage),
            findsOneWidget,
            reason: 'Root AndroidImageGridPage disposed after returning from ${entry.$1}',
          );
        }
      },
    );

    testWidgets(
      'Wide 1600x900 SearchPage loads single page without auto-cascading until user scrolls',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeSite = _FakeSiteConfigProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SiteConfigProvider>.value(value: fakeSite),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>(
                create: (_) => _FakeDownloadNotifier(),
              ),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => RecentTagsNotifier()),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SearchPage(initialTag: 'genshin_impact'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(fakeSite.fakeAdapter.requestedPages, equals([1]));

        // Explicit downward scroll triggers next page cleanly
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -2500));
        await tester.pumpAndSettle();
        expect(fakeSite.fakeAdapter.requestedPages.contains(2), isTrue);
      },
    );
  });

  group('Google Engineering Route & Navigation Benchmarks', () {
    testWidgets(
      'Benchmark: SakuraPageRoute 10x push/pop & Full 6-subpage Drawer navigation tour',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final routeSw = Stopwatch()..start();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).push(
                        SakuraPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: const Text('Child')),
                            body: const SizedBox.expand(),
                          ),
                        ),
                      );
                    },
                    child: const Text('PushRoute'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (int i = 0; i < 10; i++) {
          await tester.tap(find.text('PushRoute'));
          await tester.pumpAndSettle();
          expect(find.text('Child'), findsOneWidget);
          Navigator.of(tester.element(find.text('Child'))).pop();
          await tester.pumpAndSettle();
          expect(find.text('PushRoute'), findsOneWidget);
        }
        routeSw.stop();
        // ignore: avoid_print
        print(
          '[BENCHMARK] SakuraPageRoute 10x push+pop: ${routeSw.elapsedMilliseconds}ms '
          '(avg ${(routeSw.elapsedMilliseconds / 10).toStringAsFixed(1)}ms/trip)',
        );
        expect(routeSw.elapsedMilliseconds, lessThan(8000));

        final fakeSite = _FakeSiteConfigProvider();
        final tourSw = Stopwatch()..start();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SiteConfigProvider>.value(value: fakeSite),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>(
                create: (_) => _FakeDownloadNotifier(),
              ),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => RecentTagsNotifier()),
            ],
            child: MaterialApp(
              home: const AndroidImageGridPage(),
              routes: {
                '/downloads': (_) => const DownloadedImagesDisplay(),
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final label in ['下载', '历史', '黑名单', '账号', '设置', '关于']) {
          await tester.tap(find.byTooltip('导航菜单'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('返回'));
          await tester.pumpAndSettle();
          expect(find.byType(AndroidImageGridPage), findsOneWidget);
        }
        tourSw.stop();
        // ignore: avoid_print
        print(
          '[BENCHMARK] Full 6-subpage Drawer navigation tour: ${tourSw.elapsedMilliseconds}ms '
          '(avg ${(tourSw.elapsedMilliseconds / 6).toStringAsFixed(1)}ms/page)',
        );
        expect(tourSw.elapsedMilliseconds, lessThan(10000));
      },
    );
  });

  group('JHenTai QuickSearch, Strict Multi-Hop Search Stack & Group Download Tests', () {
    testWidgets(
      'Home bar hides SakuraView name and opens QuickSearchDrawer only on right-half left swipe',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeSite = _FakeSiteConfigProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SiteConfigProvider>.value(value: fakeSite),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>(
                create: (_) => _FakeDownloadNotifier(),
              ),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider(create: (_) => RecentTagsNotifier()),
            ],
            child: const MaterialApp(
              title: 'SakuraView',
              home: AndroidImageGridPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Home screen top bar does not display 'SakuraView'
        expect(find.text('SakuraView'), findsNothing);

        // Left-half horizontal left-swipe must NOT open QuickSearchDrawer
        await tester.flingFrom(
          const Offset(260, 450),
          const Offset(-200, 0),
          900,
        );
        await tester.pumpAndSettle();
        expect(find.byType(QuickSearchDrawer), findsNothing);

        // Right-half horizontal left-swipe MUST open QuickSearchDrawer
        await tester.flingFrom(
          const Offset(1320, 450),
          const Offset(-220, 0),
          900,
        );
        await tester.pumpAndSettle();
        expect(find.byType(QuickSearchDrawer), findsOneWidget);
        expect(find.text('快速搜索'), findsOneWidget);
      },
    );

    testWidgets(
      'Submitting search & multi-hop Detail->Tag->Results unwind strictly without jumping to Home',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final fakeSite = _FakeSiteConfigProvider();
        final recentNotifier = RecentTagsNotifier();
        await recentNotifier.load();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SiteConfigProvider>.value(value: fakeSite),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>(
                create: (_) => _FakeDownloadNotifier(),
              ),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
              ChangeNotifierProvider<RecentTagsNotifier>.value(
                value: recentNotifier,
              ),
            ],
            child: const MaterialApp(home: AndroidImageGridPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Search tab
        await tester.tap(find.byTooltip('导航菜单'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('搜索').last);
        await tester.pumpAndSettle();
        expect(find.byType(SearchPage), findsOneWidget);

        // Enter tag and submit Search -> pushes SearchResultsPage
        await tester.enterText(find.byType(TextField).first, 'genshin_impact');
        await tester.tap(find.widgetWithText(FilledButton, '搜索'));
        await tester.pumpAndSettle();
        expect(find.byType(SearchResultsPage), findsOneWidget);
        expect(find.text('genshin_impact'), findsOneWidget);

        // Back from SearchResultsPage MUST return to SearchPage, NOT Home
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.byType(SearchResultsPage), findsNothing);
        expect(find.byType(SearchPage), findsOneWidget);
        expect(find.text('最近搜索'), findsOneWidget);

        // Tap history chip -> pushes SearchResultsPage -> tap first card -> PostDetailPage -> tap tag -> 2nd SearchResultsPage
        await tester.tap(find.widgetWithText(InputChip, 'genshin_impact'));
        await tester.pumpAndSettle();
        expect(find.byType(SearchResultsPage), findsOneWidget);

        await tester.tap(find.byType(SakuraPostCard).first);
        await tester.pumpAndSettle();
        expect(find.byType(PostDetailPage), findsOneWidget);

        // Tap 'genshin impact' tag chip inside PostDetailPage -> pushes 2nd SearchResultsPage
        await tester.ensureVisible(find.text('genshin impact').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('genshin impact').last);
        await tester.pumpAndSettle();
        expect(find.byType(SearchResultsPage), findsOneWidget);

        // Back step 1: -> returns to PostDetailPage
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.byType(PostDetailPage), findsOneWidget);

        // Back step 2: -> returns to 1st SearchResultsPage
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.byType(SearchResultsPage), findsOneWidget);

        // Back step 3: -> returns to SearchPage Hub
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(find.byType(SearchPage), findsOneWidget);
      },
    );

    testWidgets(
      'PostDetailPage 下载整组 button enqueues all sibling group posts cleanly',
      (tester) async {
        final fakeSite = _FakeSiteConfigProvider();
        final fakeDownloads = _FakeDownloadNotifier();
        final currentPost = <String, dynamic>{
          'id': 9001,
          'parent_id': 9000,
          'has_children': false,
          'site': 'yandere',
          'site_id': 'yandere',
          'width': 1000,
          'height': 1400,
          'file_ext': 'jpg',
          'rating': 'safe',
          'tags': 'test_group',
          'preview_url': '',
          'sample_url': '',
          'file_url': '',
        };

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SiteConfigProvider>.value(value: fakeSite),
              ChangeNotifierProvider(create: (_) => FavoritesNotifier()),
              ChangeNotifierProvider<BaseDownloadNotifier>.value(
                value: fakeDownloads,
              ),
            ],
            child: MaterialApp(
              home: PostDetailPage(
                postData: currentPost,
                siteName: 'yandere',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final groupBtn = find.text('下载整组');
        await tester.ensureVisible(groupBtn);
        await tester.pumpAndSettle();
        await tester.tap(groupBtn);
        await tester.pumpAndSettle();

        expect(fakeDownloads.enqueuedPosts.length, 8);
      },
    );
  });
}

class _FakeOfflineSourceAdapter extends ImageSourceAdapter {
  final List<int> requestedPages = [];

  _FakeOfflineSourceAdapter(SourceDescriptor descriptor)
      : super(descriptor: descriptor);

  @override
  PostHiveModel parsePost(Map<String, dynamic> json) =>
      PostHiveModel.fromApiMap(json);

  @override
  Future<PostHiveModel?> getPostDetail(String id) async => null;

  @override
  Future<List<Map<String, dynamic>>> fetchChildPosts(int parentId) async {
    return List<Map<String, dynamic>>.generate(8, (idx) {
      final id = parentId + idx;
      return <String, dynamic>{
        'id': id,
        'parent_id': idx == 0 ? null : parentId,
        'has_children': idx == 0,
        'site': descriptor.id,
        'site_id': descriptor.id,
        'tags': 'test_group',
        'preview_url': '',
        'sample_url': '',
        'file_url': '',
        'width': 1000,
        'height': 1400,
        'rating': 'safe',
        'file_ext': 'jpg',
      };
    });
  }

  @override
  Future<List<PostHiveModel>> searchPostsWithQuery(
    SourceSearchQuery query,
  ) async {
    requestedPages.add(query.page);
    return List<PostHiveModel>.generate(40, (idx) {
      final id = (query.page - 1) * 40 + idx + 1;
      return PostHiveModel()
        ..id = id
        ..siteName = descriptor.id
        ..tags = query.tags.isEmpty ? 'test_tag' : query.tags
        ..previewUrl = ''
        ..sampleUrl = ''
        ..fileUrl = ''
        ..width = 1000
        ..height = 1400
        ..previewWidth = 300
        ..previewHeight = 420
        ..rating = 'safe'
        ..fileExt = 'jpg';
    });
  }
}

class _FakeSiteConfigProvider extends SiteConfigProvider {
  late final _FakeOfflineSourceAdapter fakeAdapter =
      _FakeOfflineSourceAdapter(currentSource);

  @override
  ImageSourceAdapter get apiClient => fakeAdapter;

  @override
  ImageSourceAdapter adapterFor(String sourceId) => fakeAdapter;
}
