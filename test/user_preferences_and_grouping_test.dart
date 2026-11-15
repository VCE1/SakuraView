import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/core/sources/adapters/danbooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/builtin_sources.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/pages/about_page.dart';
import 'package:vce1_sakuraview/pages/post_detail_page.dart';
import 'package:vce1_sakuraview/pages/search_page.dart';
import 'package:vce1_sakuraview/pages/source_management_page.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/favorites_notifier.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/services/followed_tags_service.dart';
import 'package:vce1_sakuraview/utils/settings_page.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_post_card.dart';

class _TestDownloadNotifier extends BaseDownloadNotifier {
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
  });

  group('PostGroupHelper cross-page & reverse-order merging', () {
    test('Merges children appearing before root parent into single parent card', () {
      final batch = <Map<String, dynamic>>[
        {'id': 103, 'parent_id': 100, 'has_children': false},
        {'id': 102, 'parent_id': 100, 'has_children': false},
        {'id': 200, 'parent_id': null, 'has_children': false},
        {'id': 100, 'parent_id': null, 'has_children': true},
      ];

      final merged = PostGroupHelper.mergeAndDeduplicate(const [], batch);
      expect(merged.length, 2);
      expect(merged[0]['id'], 100);
      expect(merged[0]['has_children'], isTrue);
      expect(merged[1]['id'], 200);
      expect(merged[1]['has_children'], isFalse);
    });

    test('Merges group across pagination even when child lands on page 1 and parent on page 2', () {
      final page1 = PostGroupHelper.mergeAndDeduplicate(const [], [
        {'id': '102', 'parent_id': '100', 'has_children': false},
        {'id': 300, 'has_children': false},
      ]);
      expect(page1.length, 2);
      expect(page1[0]['has_children'], isTrue);

      final page2 = PostGroupHelper.mergeAndDeduplicate(page1, [
        {'id': 100, 'parent_id': null, 'has_children': true},
        {'id': 101, 'parent_id': 100, 'has_children': false},
        {'id': 300, 'has_children': false}, // overlapping duplicate ID
        {'id': 400, 'has_children': false},
      ]);

      expect(page2.length, 3);
      expect(page2.map((e) => e['id'].toString()).toList(), ['102', '300', '400']);
      expect(page2[0]['has_children'], isTrue);
    });

    test('Promotes standalone parent from page 1 when child arrives in page 2', () {
      final page1 = PostGroupHelper.mergeAndDeduplicate(const [], [
        {'id': 500, 'has_children': false},
      ]);
      expect(page1.length, 1);
      expect(page1[0]['has_children'], isFalse);

      final page2 = PostGroupHelper.mergeAndDeduplicate(page1, [
        {'id': 501, 'parent_id': 500, 'has_children': false},
      ]);
      expect(page2.length, 1);
      expect(page2[0]['id'], 500);
      expect(page2[0]['has_children'], isTrue);
    });
  });

  group('Share formatting & GridSizePreset calculation', () {
    test('formatShareText excludes origin source and keeps clean post link', () {
      final detailShare = SourceUrlResolver.formatShareText(
        postId: 12345,
        canonicalPostUrl: 'https://yande.re/post/show/12345',
        fallbackUrl: 'https://files.yande.re/image/raw.jpg',
        siteName: 'Yande.re',
      );
      expect(detailShare, 'Yande.re #12345\nhttps://yande.re/post/show/12345');
      expect(detailShare.contains('原出处'), isFalse);

      final viewerShare = SourceUrlResolver.formatShareText(
        postId: 99,
        canonicalPostUrl: '',
        fallbackUrl: 'https://example.com/99.png',
      );
      expect(viewerShare, 'POST #99\nhttps://example.com/99.png');
    });

    test('GridSizePreset calcColumns scales cleanly across viewports', () {
      for (final width in [400.0, 600.0, 900.0]) {
        final l = GridSizePreset.large.calcColumns(width, isLandscape: width >= 640);
        final s = GridSizePreset.standard.calcColumns(width, isLandscape: width >= 640);
        final c = GridSizePreset.compact.calcColumns(width, isLandscape: width >= 640);
        expect(l < s, isTrue, reason: 'large < standard at $width');
        expect(s < c, isTrue, reason: 'standard < compact at $width');
      }
    });
  });

  group('SettingsProvider persistence & reactive UI controls', () {
    test('Persists and loads all browsing & viewer settings', () async {
      final service = SettingsService();
      await service.setShowGroupBadge(false);
      await service.setPreloadImages(false);
      await service.setViewOriginalByDefault(true);
      await service.setGridSizePreset(GridSizePreset.large);
      await service.setFloatingNavMode(FloatingNavMode.hidden);

      final provider = SettingsProvider(service: service);
      await provider.load();

      expect(provider.showGroupBadge, isFalse);
      expect(provider.showR18Badge, isTrue);
      expect(provider.preloadImages, isFalse);
      expect(provider.viewOriginalByDefault, isTrue);
      expect(provider.gridSizePreset, GridSizePreset.large);
      expect(provider.floatingNavMode, FloatingNavMode.hidden);

      await service.setShowR18Badge(false);
      await provider.load();
      expect(provider.showR18Badge, isFalse);
    });

    test('RatingFilterMode.matchesPost filters SAFE, ALL and R18 accurately', () {
      const safePost = {'site': 'danbooru', 'rating': 'safe'};
      const qPost = {'site': 'danbooru', 'rating': 'questionable'};
      const r18Post = {'site': 'danbooru', 'rating': 'explicit'};

      expect(RatingFilterMode.all.matchesPost(safePost), isTrue);
      expect(RatingFilterMode.all.matchesPost(qPost), isTrue);
      expect(RatingFilterMode.all.matchesPost(r18Post), isTrue);

      expect(RatingFilterMode.safe.matchesPost(safePost), isTrue);
      expect(RatingFilterMode.safe.matchesPost(qPost), isFalse);
      expect(RatingFilterMode.safe.matchesPost(r18Post), isFalse);

      expect(RatingFilterMode.r18.matchesPost(safePost), isFalse);
      expect(RatingFilterMode.r18.matchesPost(qPost), isFalse);
      expect(RatingFilterMode.r18.matchesPost(r18Post), isTrue);
    });

    test('Danbooru applyPoolsPayload and PostGroupHelper fold pools & pixiv sets', () {
      final adapter = DanbooruSourceAdapter(
        descriptor: BuiltInSources.findById('danbooru')!,
      );
      final p1 = adapter.parsePost({
        'id': 11,
        'preview_file_url': 'https://cdn.example/11.jpg',
        'file_ext': 'jpg',
        'rating': 'g',
        'pixiv_id': 9001,
      });
      final p2 = adapter.parsePost({
        'id': 12,
        'preview_file_url': 'https://cdn.example/12.jpg',
        'file_ext': 'jpg',
        'rating': 'g',
        'pixiv_id': 9001,
      });
      final p3 = adapter.parsePost({
        'id': 21,
        'preview_file_url': 'https://cdn.example/21.jpg',
        'file_ext': 'jpg',
        'rating': 'g',
      });
      final p4 = adapter.parsePost({
        'id': 22,
        'preview_file_url': 'https://cdn.example/22.jpg',
        'file_ext': 'jpg',
        'rating': 'g',
      });

      DanbooruSourceAdapter.applyPoolsPayload([p1, p2, p3, p4], [
        {
          'id': 501,
          'name': 'sakura_series_comic',
          'category': 'series',
          'post_count': 2,
          'post_ids': [22, 21],
        },
      ]);

      expect(p4.poolId, 501);
      expect(p4.poolIndex, 0);
      expect(p3.poolId, 501);
      expect(p3.poolIndex, 1);

      final maps = [p1, p2, p3, p4]
          .map((e) => e.toApiMap(siteName: 'danbooru'))
          .toList();
      final merged = PostGroupHelper.mergeAndDeduplicate(const [], maps);
      // Expect 2 folded groups: pixiv:9001 -> 1 card, pool:501 -> 1 card (cover id=22 since pool_index==0)
      expect(merged.length, 2);
      expect(merged.map((e) => e['id']).toSet(), {11, 22});
      expect(merged.every(PostGroupHelper.hasGroup), isTrue);
      adapter.close();
    });

    testWidgets('SakuraPostCard toggles 图组 & R18 badges live with SettingsProvider', (tester) async {
      final settingsProvider = SettingsProvider();
      await settingsProvider.load();

      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProvider,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                child: SakuraPostCard(
                  cacheWidth: 300,
                  item: const {
                    'id': 888,
                    'site': 'yandere',
                    'has_children': true,
                    'rating': 'explicit',
                    'preview_url': '',
                    'width': 1000,
                    'height': 1000,
                  },
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('图组'), findsOneWidget);
      expect(find.text('R18'), findsOneWidget);

      await settingsProvider.setShowGroupBadge(false);
      await settingsProvider.setShowR18Badge(false);
      await tester.pump();
      expect(find.text('图组'), findsNothing);
      expect(find.text('R18'), findsNothing);
    });

    testWidgets('SettingsPage updates R18 badge switch, rating filter chips & display controls', (tester) async {
      final settingsProvider = SettingsProvider();
      await settingsProvider.load();
      final siteProvider = SiteConfigProvider();
      final themeProvider = ThemeProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
            ChangeNotifierProvider<SiteConfigProvider>.value(value: siteProvider),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('允许显示 R18 内容'), findsNothing);
      expect(find.text('显示 R18 标记'), findsOneWidget);
      expect(find.text('仅 R18'), findsOneWidget);
      expect(find.text('显示图组标记'), findsOneWidget);
      expect(find.text('大图'), findsOneWidget);
      expect(find.text('永久隐藏'), findsOneWidget);
      expect(find.text('查看图片默认加载原图 (HD)'), findsOneWidget);
      expect(find.text('预加载图片'), findsOneWidget);

      await tester.tap(find.text('仅 R18'));
      await tester.pumpAndSettle();
      expect(siteProvider.ratingFilter, RatingFilterMode.r18);

      await tester.tap(find.text('全部内容'));
      await tester.pumpAndSettle();
      expect(siteProvider.ratingFilter, RatingFilterMode.all);
      expect(siteProvider.safeMode, isFalse);

      await tester.tap(find.text('显示 R18 标记'));
      await tester.pumpAndSettle();
      expect(settingsProvider.showR18Badge, isFalse);

      await tester.tap(find.text('大图'));
      await tester.pumpAndSettle();
      expect(settingsProvider.gridSizePreset, GridSizePreset.large);

      await tester.tap(find.text('永久隐藏'));
      await tester.pumpAndSettle();
      expect(settingsProvider.floatingNavMode, FloatingNavMode.hidden);

      await tester.tap(find.text('查看图片默认加载原图 (HD)'));
      await tester.pumpAndSettle();
      expect(settingsProvider.viewOriginalByDefault, isTrue);

      await tester.tap(find.text('显示图组标记'));
      await tester.pumpAndSettle();
      expect(settingsProvider.showGroupBadge, isFalse);
    });

    testWidgets('SourceManagementPage omits dev noise and marks login-required sites', (tester) async {
      final siteProvider = SiteConfigProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<SiteConfigProvider>.value(
          value: siteProvider,
          child: const MaterialApp(home: SourceManagementPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Should scroll to Gelbooru/Rule34 and see concise auth note without verbose site blurbs
      expect(find.text('需配置 User ID 与 API Key'), findsWidgets);
      expect(find.text('导出 JSON'), findsNothing);
    });

    testWidgets('AboutPage shows requested copy, version/buildTime & official package descriptions/URLs', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AboutPage()));
      await tester.pumpAndSettle();

      expect(
        find.text('这是一款兴趣使然，由Flutter编写的轻量看图应用。目前支持多数booru系图站。'),
        findsOneWidget,
      );
      expect(find.text('当前版本'), findsOneWidget);
      expect(find.text('构建时间'), findsOneWidget);
      expect(find.text('感谢使用 SakuraView，请多多指教~'), findsOneWidget);
      expect(find.text('开源插件与致谢'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('provider'),
        220,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      expect(find.text('provider'), findsOneWidget);
      expect(find.text('https://github.com/rrousselGit/provider'), findsOneWidget);

      // Should not include removed framework rows, site lists, or external references
      expect(find.text('项目框架与逻辑'), findsNothing);
      expect(find.text('Danbooru'), findsNothing);
      expect(find.text('pixes-app/pixes'), findsNothing);
      expect(find.text('Boorusama'), findsNothing);
      expect(find.text('Venera（多源插件扩展清单规范）'), findsNothing);
    });

    testWidgets('PostDetailPage copy-share works without 3rd-party, metadata source copies, and long-press manages follow/blacklist', (tester) async {
      String? capturedSharePluginText;
      String? capturedClipboardText;
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        (call) async {
          final args = call.arguments as Map?;
          capturedSharePluginText = args?['text']?.toString();
          return 'success';
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            capturedClipboardText = (call.arguments as Map?)?['text']?.toString();
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          shareChannel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await FollowedTagsService.instance.clearAll();
      await BlacklistService.instance.clearAll();

      final siteProvider = SiteConfigProvider();
      final favNotifier = FavoritesNotifier();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SiteConfigProvider>.value(value: siteProvider),
            ChangeNotifierProvider<FavoritesNotifier>.value(value: favNotifier),
            ChangeNotifierProvider<BaseDownloadNotifier>(
              create: (_) => _TestDownloadNotifier(),
            ),
          ],
          child: const MaterialApp(
            home: PostDetailPage(
              siteName: 'yandere',
              postData: {
                'id': 777,
                'site': 'yandere',
                'site_id': 'yandere',
                'tags': 'sakura_hair dress',
                'general_tags': ['sakura_hair', 'dress'],
                'source': 'https://www.pixiv.net/artworks/999999',
                'rating': 'safe',
                'width': 1000,
                'height': 1000,
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // 1. Share sheet offers clipboard copy without invoking 3rd-party app
      await tester.ensureVisible(find.text('分享'));
      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();

      expect(find.text('复制分享内容'), findsOneWidget);
      expect(find.text('通过第三方应用分享'), findsOneWidget);
      await tester.tap(find.text('复制分享内容'));
      await tester.pumpAndSettle();

      expect(capturedSharePluginText, isNull);
      expect(capturedClipboardText, contains('Yande.re #777'));
      expect(capturedClipboardText, contains('https://yande.re/post/show/777'));
      expect(capturedClipboardText, isNot(contains('原出处')));
      expect(capturedClipboardText, isNot(contains('pixiv.net')));

      // 2. Third-party share still works when explicitly selected
      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('通过第三方应用分享'));
      await tester.pumpAndSettle();
      expect(capturedSharePluginText, contains('Yande.re #777'));

      // 3. Metadata section uses SelectionArea & provides one-tap copy for 作品来源
      expect(find.byType(SelectionArea), findsOneWidget);
      final copySourceBtn = find.byTooltip('复制作品来源');
      await tester.scrollUntilVisible(
        copySourceBtn,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(copySourceBtn);
      await tester.pumpAndSettle();
      expect(capturedClipboardText, 'https://www.pixiv.net/artworks/999999');

      // 4. Long-press tag manages 特别关注 & 黑名单, then appears in SearchPage
      final tagFinder = find.text('sakura hair');
      await tester.scrollUntilVisible(
        tagFinder,
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.longPress(tagFinder);
      await tester.pumpAndSettle();

      expect(find.text('加入特别关注'), findsOneWidget);
      expect(find.text('加入标签黑名单'), findsOneWidget);
      await tester.tap(find.text('加入特别关注'));
      await tester.pumpAndSettle();
      expect(FollowedTagsService.instance.isFollowed('sakura_hair'), isTrue);

      await tester.longPress(tagFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入标签黑名单'));
      await tester.pumpAndSettle();
      expect(BlacklistService.instance.isBlocked('sakura_hair'), isTrue);

      // 5. Verify SearchPage shows 特别关注 section
      final recentNotifier = RecentTagsNotifier();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SiteConfigProvider>.value(value: siteProvider),
            ChangeNotifierProvider<RecentTagsNotifier>.value(value: recentNotifier),
          ],
          child: const MaterialApp(home: SearchPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('特别关注'), findsOneWidget);
      expect(find.text('sakura hair'), findsOneWidget);
    });
  });
}
