import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/services/history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BlacklistService Unit Tests', () {
    test('addTag, removeTag, and isPostBlocked work correctly', () async {
      final service = BlacklistService.instance;
      await service.ensureInitialized();
      await service.clearAll();

      expect(service.isEmpty, isTrue);

      final added = await service.addTag('gore');
      expect(added, isTrue);
      expect(service.tags.contains('gore'), isTrue);

      // Duplicates rejected
      final addedAgain = await service.addTag('GORE');
      expect(addedAgain, isFalse);
      expect(service.count, 1);

      // Post blocking test
      final postWithGore = {
        'id': 100,
        'tags': 'solo smile gore 1girl',
      };
      final postSafe = {
        'id': 101,
        'tags': 'solo smile beautiful 1girl',
      };

      expect(service.isPostBlocked(postWithGore), isTrue);
      expect(service.isPostBlocked(postSafe), isFalse);

      // Remove tag
      final removed = await service.removeTag('gore');
      expect(removed, isTrue);
      expect(service.isPostBlocked(postWithGore), isFalse);
    });
  });

  group('HistoryService Unit Tests', () {
    test('addHistory, getHistory, remove, and clear work correctly', () async {
      final service = HistoryService.instance;
      await service.clearHistory();

      final list0 = await service.getHistory();
      expect(list0.isEmpty, isTrue);

      await service.addHistory({
        'id': 12345,
        'site': 'yande.re',
        'preview_url': 'https://example.com/preview.jpg',
        'file_url': 'https://example.com/file.jpg',
        'rating': 's',
      });

      final list1 = await service.getHistory();
      expect(list1.length, 1);
      expect(list1.first['id'], 12345);

      await service.removeHistoryItem('12345');
      final list2 = await service.getHistory();
      expect(list2.isEmpty, isTrue);
    });

    test('addHistory preserves full uploader, artist, site_id, tags & group metadata', () async {
      final service = HistoryService.instance;
      await service.clearHistory();

      await service.addHistory({
        'id': 778899,
        'site': 'zerochan',
        'site_id': 'zerochan',
        'uploader': 'PhoenixNight',
        'creator_id': 1878347,
        'author': 'Ringeko',
        'artist_tags': ['Ringeko'],
        'character_tags': ['Si_(Arknights:_Endfield)'],
        'copyright_tags': ['Arknights:_Endfield'],
        'general_tags': ['Green_Dress'],
        'meta_tags': ['Fanart'],
        'parent_id': 778800,
        'has_children': true,
        'source': 'https://www.patreon.com/posts/174456444',
        'created_at': 1762970531,
        'file_size': 4215808,
        'file_ext': 'jpg',
        'score': 12,
        'preview_url': 'https://example.com/p.jpg',
        'sample_url': 'https://example.com/s.jpg',
        'file_url': 'https://example.com/f.jpg',
        'rating': 'unknown',
        'tags': 'Ringeko Green_Dress',
      });

      final list = await service.getHistory();
      expect(list.length, 1);
      final saved = list.first;
      expect(saved['site_id'], 'zerochan');
      expect(saved['uploader'], 'PhoenixNight');
      expect(saved['creator_id'], 1878347);
      expect(saved['author'], 'Ringeko');
      expect(saved['artist_tags'], ['Ringeko']);
      expect(saved['character_tags'], ['Si_(Arknights:_Endfield)']);
      expect(saved['copyright_tags'], ['Arknights:_Endfield']);
      expect(saved['parent_id'], 778800);
      expect(saved['has_children'], isTrue);
      expect(saved['file_size'], 4215808);
    });
  });
}
