import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/api/yande_api.dart';
import 'package:vce1_sakuraview/core/sources/adapters/danbooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/eshuushuu_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/gelbooru_family_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/moebooru_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/adapters/zerochan_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/builtin_sources.dart';
import 'package:vce1_sakuraview/core/sources/image_source_adapter.dart';
import 'package:vce1_sakuraview/core/sources/source_adapter_factory.dart';
import 'package:vce1_sakuraview/core/sources/source_config_parser.dart';
import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/models/post_hive_model.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

void main() {
  group('ContentRating Normalization Tests', () {
    test('Distinguishes Danbooru/Gelbooru s (sensitive) vs Moebooru/Safebooru s (safe)', () {
      expect(
        ContentRating.parse('g', siteId: 'danbooru'),
        ContentRating.safe,
      );
      expect(
        ContentRating.parse('s', siteId: 'danbooru'),
        ContentRating.sensitive,
      );
      expect(
        ContentRating.parse('g', siteId: 'gelbooru'),
        ContentRating.safe,
      );
      expect(
        ContentRating.parse('s', siteId: 'gelbooru'),
        ContentRating.sensitive,
      );
      expect(
        ContentRating.parse('s', siteId: 'yandere'),
        ContentRating.safe,
      );
      expect(
        ContentRating.parse('s', siteId: 'konachan'),
        ContentRating.safe,
      );
      expect(
        ContentRating.parse('s', siteId: 'rule34'),
        ContentRating.safe,
      );
      expect(
        ContentRating.parse('s', siteId: 'safebooru'),
        ContentRating.safe,
      );
    });

    test('Missing/empty rating and E-Shuushuu star ratings strictly stay unknown', () {
      expect(ContentRating.parse(null, siteId: 'zerochan'), ContentRating.unknown);
      expect(ContentRating.parse('', siteId: 'danbooru'), ContentRating.unknown);
      expect(
        ContentRating.parse('8.7', siteId: 'eshuushuu'),
        ContentRating.unknown,
      );
      expect(ContentRating.unknown.label, '未知');
    });
  });

  group('SourceUrlResolver Tests', () {
    test('Canonicalizes Pixiv i.pximg.net and legacy URLs to artworks URLs', () {
      expect(
        SourceUrlResolver.normalizeSourceUrls(
          'https://i.pximg.net/img-original/img/2026/05/01/12/00/00/152004614_p0.jpg',
        ),
        ['https://www.pixiv.net/artworks/152004614'],
      );
      expect(
        SourceUrlResolver.normalizeSingleUrl(
          'https://www.pixiv.net/member_illust.php?mode=medium&illust_id=987654',
        ),
        'https://www.pixiv.net/artworks/987654',
      );
    });

    test('Detects video media extensions and resolves canonical post URLs', () {
      expect(
        SourceUrlResolver.isVideoMedia(
          url: 'https://www.sakugabooru.com/data/12345.mp4',
        ),
        isTrue,
      );
      expect(
        SourceUrlResolver.isVideoMedia(
          url: 'https://konachan.com/image/abc.png',
        ),
        isFalse,
      );
      expect(
        SourceUrlResolver.canonicalPostUrl(siteId: 'konachan', postId: 391002),
        'https://konachan.com/post/show/391002',
      );
      expect(
        SourceUrlResolver.canonicalPostUrl(siteId: 'eshuushuu', postId: 112233),
        'https://e-shuushuu.net/images/112233',
      );
    });
  });

  group('BuiltInSources Isolation & JSON Parser Tests', () {
    test('Legacy 3 sources enabled; TBIB removed & remaining 5 newly adapted sources disabled by default', () {
      for (final legacyId in ['yandere', 'danbooru', 'zerochan']) {
        final s = BuiltInSources.findById(legacyId);
        expect(s, isNotNull);
        expect(s!.defaultEnabled, isTrue);
        expect(s.isEnabled, isTrue);
      }

      expect(BuiltInSources.findById('tbib'), isNull);
      expect(
        SourceEngineType.fromName('tbib'),
        SourceEngineType.customBooruJson,
      );

      const newlyAdaptedIds = [
        'konachan',
        'gelbooru',
        'rule34',
        'sakugabooru',
        'eshuushuu',
      ];
      for (final id in newlyAdaptedIds) {
        final s = BuiltInSources.findById(id);
        expect(s, isNotNull, reason: 'Missing built-in source $id');
        expect(s!.defaultEnabled, isFalse, reason: '$id defaultEnabled must be false');
        expect(s.isEnabled, isFalse, reason: '$id isEnabled must be false');
      }
    });

    test('SourceConfigParser forces imported sources disabled and rejects malformed manifests', () {
      const payload = '''
      {
        "sources": [
          {
            "id": "demo_site",
            "name": "Demo Booru",
            "engine": "moebooru",
            "baseUrl": "https://demo.example.com",
            "isEnabled": true,
            "defaultEnabled": true
          }
        ]
      }''';
      final imported = SourceConfigParser.parseImportPayload(payload);
      expect(imported.length, 1);
      expect(imported.first.id, 'demo_site');
      expect(imported.first.isEnabled, isFalse);

      expect(
        () => SourceConfigParser.parseImportPayload('{"id": "BAD ID!", "name": "x", "baseUrl": "ftp://a"}'),
        throwsFormatException,
      );
    });
  });

  group('Newly Adapted Source Parsers Tests', () {
    test('MoebooruSourceAdapter (Konachan v2) separates uploader author vs artist tags', () {
      final konachanDesc = BuiltInSources.findById('konachan')!;
      final adapter =
          SourceAdapterFactory.create(descriptor: konachanDesc) as MoebooruSourceAdapter;

      const v2Json = '''
      {
        "posts": [
          {
            "id": 388101,
            "tags": "artist_alpha circle_beta char_gamma copyright_delta blue_eyes",
            "author": "uploader_account",
            "creator_id": 55,
            "source": "https://i.pximg.net/img-original/img/2026/01/01/00/00/00/123456789_p0.jpg",
            "rating": "s",
            "score": 88,
            "width": 2000,
            "height": 1400,
            "preview_url": "https://konachan.com/data/preview/388101.jpg",
            "sample_url": "https://konachan.com/sample/388101.jpg",
            "file_url": "https://konachan.com/image/388101.png",
            "parent_id": 388100,
            "has_children": false
          }
        ],
        "tags": {
          "artist_alpha": "artist",
          "circle_beta": "circle",
          "char_gamma": "character",
          "copyright_delta": "copyright",
          "blue_eyes": "general"
        }
      }''';

      final posts = adapter.parsePostsPayload(v2Json);
      expect(posts.length, 1);
      final p = posts.first;
      expect(p.uploader, 'uploader_account');
      expect(p.artistTags, ['artist_alpha', 'circle_beta']);
      expect(p.characterTags, ['char_gamma']);
      expect(p.copyrightTags, ['copyright_delta']);
      expect(p.generalTags, ['blue_eyes']);
      expect(p.rating, 'safe');
      expect(p.parentId, 388100);
    });

    test('MoebooruSourceAdapter (Sakugabooru) protects mp4 preview image', () {
      final sakugaDesc = BuiltInSources.findById('sakugabooru')!;
      final adapter =
          SourceAdapterFactory.create(descriptor: sakugaDesc) as MoebooruSourceAdapter;

      const body = '''
      {
        "posts": [
          {
            "id": 250100,
            "tags": "animator_yutaka effects",
            "author": "sakuga_up",
            "rating": "s",
            "width": 1920,
            "height": 1080,
            "preview_url": "https://www.sakugabooru.com/data/preview/250100.jpg",
            "sample_url": "https://www.sakugabooru.com/data/sample/250100.mp4",
            "file_url": "https://www.sakugabooru.com/data/250100.mp4",
            "file_ext": "mp4"
          }
        ],
        "tags": {
          "animator_yutaka": "artist",
          "effects": "general"
        }
      }''';

      final posts = adapter.parsePostsPayload(body);
      expect(posts.length, 1);
      final p = posts.first;
      expect(p.sampleUrl, 'https://www.sakugabooru.com/data/preview/250100.jpg');
      expect(p.fileUrl, endsWith('.mp4'));
      expect(p.artistTags, ['animator_yutaka']);
      expect(p.uploader, 'sakuga_up');
    });

    test('GelbooruFamilySourceAdapter parses Gelbooru JSON & Safebooru XML cleanly', () {
      final gelDesc = BuiltInSources.findById('gelbooru')!;
      final gelAdapter =
          SourceAdapterFactory.create(descriptor: gelDesc) as GelbooruFamilySourceAdapter;

      const gelJson = '''
      {
        "post": [
          {
            "id": 9100222,
            "owner": "gel_uploader",
            "creator_id": 44,
            "rating": "general",
            "width": 1200,
            "height": 1800,
            "tags": "solo long_hair",
            "preview_url": "https://img3.gelbooru.com/thumbnails/a/b/thumbnail_9100222.jpg",
            "sample_url": "https://img3.gelbooru.com/samples/a/b/sample_9100222.jpg",
            "file_url": "https://img3.gelbooru.com/images/a/b/9100222.png"
          }
        ]
      }''';
      final gelPosts = gelAdapter.parseJsonPostsPayload(gelJson);
      expect(gelPosts.length, 1);
      expect(gelPosts.first.uploader, 'gel_uploader');
      expect(gelPosts.first.artistTags, isNull);
      expect(gelPosts.first.rating, 'safe');

      const xmlCustomDesc = SourceDescriptor(
        id: 'safebooru',
        name: 'Safebooru',
        engine: SourceEngineType.gelbooruXml,
        baseUrl: 'https://safebooru.org',
      );
      final xmlAdapter = SourceAdapterFactory.create(descriptor: xmlCustomDesc)
          as GelbooruFamilySourceAdapter;
      const safeXml = '''
      <posts count="1" offset="0">
        <post height="900" width="1600" score="12"
          file_url="//safebooru.org/images/777/full.png"
          sample_url="//safebooru.org/samples/777/sample.jpg"
          preview_url="//safebooru.org/thumbnails/777/thumb.jpg"
          tags="sky clouds" id="777111" rating="s" creator_id="99" />
      </posts>''';
      final xmlPosts = xmlAdapter.parseXmlPostsPayload(safeXml);
      expect(xmlPosts.length, 1);
      expect(xmlPosts.first.id, 777111);
      expect(xmlPosts.first.fileUrl, 'https://safebooru.org/images/777/full.png');
      expect(xmlPosts.first.rating, 'safe');
    });

    test('EShuushuuSourceAdapter parses 4 tag categories and retains unknown content rating', () {
      final desc = BuiltInSources.findById('eshuushuu')!;
      final adapter =
          SourceAdapterFactory.create(descriptor: desc) as EShuushuuSourceAdapter;

      const body = '''
      {
        "images": [
          {
            "image_id": 1122334,
            "filename": "2026-03-10-1122334",
            "ext": "png",
            "width": 1600,
            "height": 2200,
            "large": 1,
            "rating": 9.2,
            "user": { "user_id": 77, "username": "es_member" },
            "tags": [
              { "title": "Blue Archive", "type": 2 },
              { "title": "Hina", "type": 4 },
              { "title": "Artist Name", "type": 3 },
              { "title": "halo", "type": 1 }
            ]
          }
        ]
      }''';
      final posts = adapter.parseImagesPayload(body);
      expect(posts.length, 1);
      final p = posts.first;
      expect(p.copyrightTags, ['Blue_Archive']);
      expect(p.characterTags, ['Hina']);
      expect(p.artistTags, ['Artist_Name']);
      expect(p.generalTags, ['halo']);
      expect(p.uploader, 'es_member');
      expect(p.rating, 'unknown');
      expect(p.previewUrl, 'https://cdn.e-shuushuu.net/thumbs/2026-03-10-1122334.webp');
      expect(p.fileUrl, 'https://cdn.e-shuushuu.net/fullsize/2026-03-10-1122334.png');
    });
  });

  group('Download Metadata Persistence & Search Matching Tests', () {
    test('PostHiveModel roundtrips group/site/uploader/tag categories and DownloadedItem searches all axes', () {
      final apiMap = <String, dynamic>{
        'id': 556677,
        'site': 'konachan',
        'site_id': 'konachan',
        'parent_id': 556600,
        'has_children': false,
        'uploader': 'up_chan',
        'artist_tags': ['artist_kuro'],
        'character_tags': ['hatsune_miku'],
        'copyright_tags': ['vocaloid'],
        'general_tags': ['twintails'],
        'meta_tags': ['highres'],
        'preview_width': 300,
        'preview_height': 420,
        'width': 2400,
        'height': 3360,
        'rating': 'safe',
        'tags': 'vocaloid hatsune_miku artist_kuro twintails highres',
        'file_url': 'https://konachan.com/image/556677.png',
        'sample_url': 'https://konachan.com/sample/556677.jpg',
        'preview_url': 'https://konachan.com/preview/556677.jpg',
      };

      final hive = PostHiveModel.fromApiMap(apiMap);
      final roundtrip = hive.toApiMap();
      expect(roundtrip['parent_id'], 556600);
      expect(roundtrip['uploader'], 'up_chan');
      expect(roundtrip['artist_tags'], ['artist_kuro']);
      expect(roundtrip['copyright_tags'], ['vocaloid']);
      expect(roundtrip['preview_width'], 300);

      final dlItem = DownloadedItem(
        id: '556677',
        filePath: '/tmp/556677.png',
        filename: '556677.png',
        creationDate: DateTime(2026, 5, 1),
        author: 'artist_kuro',
        uploader: 'up_chan',
        siteName: 'konachan',
        artistTags: const ['artist_kuro'],
        characterTags: const ['hatsune_miku'],
        copyrightTags: const ['vocaloid'],
        generalTags: const ['twintails'],
        metaTags: const ['highres'],
        parentId: 556600,
      );

      expect(dlItem.matchesSearchQuery('artist_kuro'), isTrue);
      expect(dlItem.matchesSearchQuery('up_chan'), isTrue);
      expect(dlItem.matchesSearchQuery('vocaloid'), isTrue);
      expect(dlItem.matchesSearchQuery('556600'), isTrue);
      expect(dlItem.matchesSearchQuery('artist:kuro'), isTrue);
      expect(dlItem.matchesSearchQuery('uploader:up_chan'), isTrue);
      expect(dlItem.matchesSearchQuery('parent:556600', onlyGroups: true), isTrue);
      expect(dlItem.matchesSearchQuery('artist:someone_else'), isFalse);

      final targetOrig = DownloadMetadataHelper.resolveDownloadTarget(
        apiMap,
        DownloadQuality.original,
      );
      final targetSample = DownloadMetadataHelper.resolveDownloadTarget(
        apiMap,
        DownloadQuality.sample,
      );
      expect(targetOrig.url, 'https://konachan.com/image/556677.png');
      expect(targetSample.url, 'https://konachan.com/sample/556677.jpg');
    });

    test('Zerochan HTML enriches uploader, creatorId, categorized tags & artist separately', () {
      final zcDesc = BuiltInSources.findById('zerochan')!;
      expect(zcDesc.capabilities.supportsUploaderFilter, isTrue);

      final adapter = ZerochanSourceAdapter(descriptor: zcDesc);
      final post = adapter.parsePost({
        'id': 4736106,
        'width': 5579,
        'height': 4000,
        'small': 'https://s1.zerochan.net/75/06/22/4736106.jpg',
        'large': 'https://s1.zerochan.net/Si.%28Arknights%3A.Endfield%29.600.4736106.jpg',
        'full': 'https://static.zerochan.net/Si.%28Arknights%3A.Endfield%29.full.4736106.jpg',
        'primary': 'Si (Arknights: Endfield)',
        'tags': [
          'Ringeko',
          'Arknights: Endfield',
          'Si (Arknights: Endfield)',
          'Green Dress',
          'Fanart',
        ],
      });

      const sampleHtml = '''
      <html><body>
        <script type="application/ld+json">{
          "@context":"http://schema.org",
          "@type":"ImageObject",
          "author":{"@type":"Person","name":"Ringeko"},
          "datePublished":"2026-11-12T18:02:11+00:00"
        }</script>
        <p>Uploaded by <a class="user" href="/user/PhoenixNight" data-user="PhoenixNight"><img src="https://s1.zerochan.net/avatars50/1878347.webp">PhoenixNight</a></p>
        <ul id="tags" class="tags ">
          <li class="mangaka" data-tag="Ringeko"><a href="/Ringeko" data-tag="Ringeko">Ringeko</a></li>
          <li class="game" data-tag="Arknights: Endfield"><a href="/Arknights%3A+Endfield" data-tag="Arknights: Endfield">Arknights: Endfield</a></li>
          <li class="character primary" data-tag="Si (Arknights: Endfield)"><a href="/Si+%28Arknights%3A+Endfield%29">Si (Arknights: Endfield)</a></li>
          <li class="source" data-tag="Fanart"><a href="/Fanart">Fanart</a></li>
        </ul>
      </body></html>
      ''';

      ZerochanSourceAdapter.enrichPostFromHtml(post, sampleHtml);

      expect(post.uploader, 'PhoenixNight');
      expect(post.creatorId, 1878347);
      expect(post.author, 'Ringeko');
      expect(post.artistTags, ['Ringeko']);
      expect(post.copyrightTags, ['Arknights:_Endfield']);
      expect(post.characterTags, ['Si_(Arknights:_Endfield)']);
      expect(post.metaTags, ['Fanart']);
      expect(post.generalTags, ['Green_Dress']);
      expect(post.createdAt, isNotNull);

      final q1 = ImageSourceAdapter.extractUploaderFromQuery(
        const SourceSearchQuery(tags: 'user:PhoenixNight Solo'),
      );
      expect(q1.uploader, 'PhoenixNight');
      expect(q1.remainingTags, 'Solo');

      final q2 = ImageSourceAdapter.extractUploaderFromQuery(
        const SourceSearchQuery(tags: 'user:"Alice Bob" Solo'),
      );
      expect(q2.uploader, 'Alice Bob');
      expect(q2.remainingTags, 'Solo');
    });

    test('Danbooru parseUsersPayload resolves batch /users.json IDs safely', () {
      final resolved = DanbooruSourceAdapter.parseUsersPayload([
        {'id': 42, 'name': 'dan_uploader_a'},
        {'id': '99', 'name': 'dan_uploader_b'},
        {'id': 0, 'name': 'ignored'},
      ]);
      expect(resolved, {42: 'dan_uploader_a', 99: 'dan_uploader_b'});
    });

    test('Gelbooru family enrichPostFromViewHtml extracts uploader & tag categories and skips wiki links', () {
      final post = PostHiveModel()
        ..id = 28917443
        ..siteName = 'gelbooru'
        ..tags = 'pierre_(cowprintsoda) rabbit danganronpa_(series) solo';

      const html = '''
      <html><body>
        <ul>
          <li>Posted: 2026-11-13 06:37:28<br /> by <a href="index.php?page=account&amp;s=profile&amp;uname=Anonymous">Anonymous</a></li>
        </ul>
        <ul id="tag-sidebar">
          <li class="tag-type-artist tag">
            <a href="index.php?page=wiki&s=list&search=pierre_%28cowprintsoda%29">?</a>
            <a href="index.php?page=post&amp;s=list&amp;tags=pierre_%28cowprintsoda%29">pierre (cowprintsoda)</a>
          </li>
          <li class="tag-type-copyright tag">
            <a href="index.php?page=wiki&s=list&search=danganronpa_%28series%29">?</a>
            <a href="index.php?page=post&amp;s=list&amp;tags=danganronpa_%28series%29">danganronpa (series)</a>
          </li>
          <li class="tag-type-character tag">
            <a href="index.php?page=post&amp;s=list&amp;tags=rabbit">rabbit</a>
          </li>
          <li class="tag-type-general tag">
            <a href="index.php?page=post&amp;s=list&amp;tags=solo">solo</a>
          </li>
        </ul>
      </body></html>
      ''';

      GelbooruFamilySourceAdapter.enrichPostFromViewHtml(post, html);

      expect(post.uploader, 'Anonymous');
      expect(post.artistTags, ['pierre_(cowprintsoda)']);
      expect(post.author, 'pierre_(cowprintsoda)');
      expect(post.copyrightTags, ['danganronpa_(series)']);
      expect(post.characterTags, ['rabbit']);
      expect(post.generalTags, ['solo']);
    });

    test('YandeApi.parseChildPostsPayload separates v2 uploader from artist tags', () {
      final parsed = YandeApi.parseChildPostsPayload({
        'posts': [
          {
            'id': 8801,
            'tags': 'blue_sky suzukawa_rin hatsune_miku vocaloid',
            'author': 'himeno_nanako',
            'creator_id': 77,
            'file_url': 'https://files.yande.re/image/8801.png',
          },
        ],
        'tags': {
          'suzukawa_rin': 'artist',
          'hatsune_miku': 'character',
          'vocaloid': 'copyright',
          'blue_sky': 'general',
        },
      });
      expect(parsed.length, 1);
      final p = parsed.first;
      expect(p['uploader'], 'himeno_nanako');
      expect(p['author'], 'suzukawa_rin');
      expect(p['artist_tags'], ['suzukawa_rin']);
      expect(p['character_tags'], ['hatsune_miku']);
      expect(p['copyright_tags'], ['vocaloid']);
      expect(p['general_tags'], ['blue_sky']);
    });

    test('DownloadMetadataHelper.enrichBeforeDownload populates uploader, artist & full URL', () async {
      final enriched = await DownloadMetadataHelper.enrichBeforeDownload(
        {
          'id': 4736106,
          'site': 'zerochan',
          'site_id': 'zerochan',
          'file_url': 'https://s1.zerochan.net/test.600.4736106.jpg',
          'sample_url': 'https://s1.zerochan.net/test.600.4736106.jpg',
        },
        DownloadQuality.original,
        detailFetcher: (siteId, postId) async => PostHiveModel()
          ..id = 4736106
          ..siteName = siteId
          ..uploader = 'PhoenixNight'
          ..creatorId = 1878347
          ..author = 'Ringeko'
          ..artistTags = const ['Ringeko']
          ..fileUrl = 'https://static.zerochan.net/test.full.4736106.jpg',
      );

      expect(enriched['uploader'], 'PhoenixNight');
      expect(enriched['creator_id'], 1878347);
      expect(enriched['author'], 'Ringeko');
      expect(enriched['artist_tags'], ['Ringeko']);
      expect(enriched['file_url'], 'https://static.zerochan.net/test.full.4736106.jpg');
    });

    test('Danbooru parseProfilePayload, Cloudflare detector & QuickSearch persistence work cleanly', () async {
      final profile = DanbooruSourceAdapter.parseProfilePayload({
        'id': 654321,
        'name': 'sakura_user',
      });
      expect(profile, isNotNull);
      expect(profile!.name, 'sakura_user');
      expect(profile.id, '654321');
      expect(
        DanbooruSourceAdapter.parseProfilePayload({'id': 0, 'name': 'Anonymous'}),
        isNull,
      );

      final cfRes = http.Response(
        '<html><title>Just a moment...</title></html>',
        403,
        headers: {'cf-mitigated': 'challenge'},
      );
      expect(DanbooruSourceAdapter.isCloudflareChallengeResponse(cfRes), isTrue);
      expect(
        DanbooruSourceAdapter.isCloudflareChallengeResponse(
          http.Response('[]', 200),
        ),
        isFalse,
      );

      // Verify legacy persisted 'tbib' override is stripped safely on load
      SharedPreferences.setMockInitialValues({
        'source_registry_v2':
            '{"currentSourceId":"tbib","enabledOverrides":{"tbib":true,"konachan":false}}',
      });
      final siteProvider = SiteConfigProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(siteProvider.findSourceById('tbib'), isNull);
      expect(
        siteProvider.enabledSources.any((s) => s.id == 'tbib'),
        isFalse,
      );
      expect(siteProvider.currentSourceId, isNot('tbib'));
      expect(siteProvider.findSourceById('konachan')?.isEnabled, isFalse);

      final tagsNotifier = RecentTagsNotifier();
      await tagsNotifier.load();
      await tagsNotifier.addQuickSearch(
        label: '蓝眼',
        query: 'blue_eyes',
        artist: 'artist_z',
      );
      expect(tagsNotifier.quickSearches.length, 1);
      expect(
        tagsNotifier.hasQuickSearch(
          query: 'blue_eyes',
          artist: 'artist_z',
        ),
        isTrue,
      );

      final tagsReloaded = RecentTagsNotifier();
      await tagsReloaded.load();
      expect(tagsReloaded.quickSearches.first.label, '蓝眼');
    });
  });
}
