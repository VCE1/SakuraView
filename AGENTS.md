# Agent Session Log

## Project: SakuraView (vce1_sakuraview)
- Multi-site image viewer for Danbooru, Yande.re, Zerochan
- Flutter 3.44.4, Material 3, Android + Windows
- Package import: `package:vce1_sakuraview/`
- Font: Google Fonts Quicksand (already chosen)
- Design reference: [Pix-EzViewer](https://github.com/ultranity/Pix-EzViewer)
- All login/auth functionality has been REMOVED (no AuthProvider, no login page, no user model, no user API service)

## Current Build State
- `flutter analyze`: **0 errors, 0 warnings, 0 info-level hints** (Session 7)
- Windows build: ✅ **builds** to `build\windows\x64\runner\Release\sakuraview.exe`
- Android build: ✅ **builds** debug APK (with Kotlin plugin warnings from external packages)
- Proxy settings page accessible via Settings → Network

## Key Architecture

### API Layer
```
ImageApiClient (abstract)           ← proxy-aware httpGet()
  ├── DanbooruApiClient             ← httpGet(uri)
  ├── YandereApiClient              ← httpGet(uri)
  └── ZerochanApiClient             ← httpGet(uri)

YandeApi (static util)              ← fetchChildPosts() only, uses ProxyConfig directly
ApiClientFactory                    ← creates ImageApiClient by site
```

### Proxy System
- `ProxyConfig.createClient()` — reads SharedPreferences, creates `IOClient` with `findProxy` set
- Default address: `127.0.0.1:7897`, **enabled by default**
- `ImageApiClient.httpGet()` — creates **new client per request**, closes in `finally` — ensures proxy settings always picked up
- Test button in proxy settings page
- Startup test runs in `main.dart`

### Theme System (Session 5)
- 4 variants: Sakura Light, Sakura Dark, Pure Black (AMOLED), Follow System
- Stored as string in SharedPreferences (`theme_variant` key)
- `ThemeVariant` enum with `.label`, `.isDark`
- Provider exposes `.theme`, `.darkTheme`, `.themeMode`
- UI selectors in drawer (ExpansionTile) and settings (dialog)

### Logging (Session 6)
- `Logger.root.level = Level.ALL` in main.dart, outputs via `debugPrint`
- `ProxyConfig.createClient()` logs: enabled, address, proxy directive, errors
- `ImageApiClient.httpGet()` logs: site, URL, timing, status code, errors
- Startup proxy test: `ProxyConfig.testConnection()` prints PASS/FAIL

### Session 6 — API client refactoring (conform to documented APIs)
- **Zerochan**: Fixed URL structure — tags go in URL path (not query params), uses `?json&p=...&l=...` with correct param names (`p`, `l`, `s`). Post detail uses `/{id}?json`. User-Agent includes username.
- **Yande.re**: Fixed tag search parameter from `name__like` (Danbooru API) to `name_pattern` (Moebooru API)
- **Danbooru**: User-Agent now includes username in recommended format `"vce1.sakuraview/1.0 (username)"` when available
- Cleaned up `site_config.dart`: removed unused `tagSearchPath`, `postsSearchPath`, `postDetailPath` helpers (clients use their own URL construction)
- API docs added to AGENTS.md for quick reference by future AI models

## Session History

### Session 1 — Fix corrupted strings + compilation
- Fixed ~30 corrupted Chinese strings in `yande_api.dart`
- Fixed `app_theme.dart`, `site_config.dart`, all missing imports
- Rewrote 10+ files with clean English strings
- `flutter analyze` went from ~30 errors → 0 errors

### Session 2 — Fix Windows build
- Removed `permission_handler` dependency (caused NuGet dependency on Windows)
- Simplified download permission (always true — modern scoped storage doesn't need it)
- Fixed CMake install prefix to avoid admin elevation
- Windows build now succeeds

### Session 3 — Glassmorphism UI
- Dark theme in `app_theme.dart`, NavigationBar/Drawer/BottomSheet themes
- Bottom NavigationBar (Home/Search/Favorites/Downloads) in `android_page.dart`
- `search_page.dart`: tag input, masonry grid, scroll-to-load-more, `initialTag` + `didUpdateWidget`
- `drawer_widget.dart`: modern header, site selection, theme toggle
- `android_full_image_screen.dart`: glass AppBar, "View original" overlay, `_TagChip` navigates with tag pop

### Session 4 — Theme toggle + search nav
- `ThemeProvider`: SharedPreferences persistence, toggle between light/dark
- Settings page: Appearance section with switch
- Tag chips in full-image screen → `Navigator.pop(context, tag)` → search page pre-fills

### Session 5 (current major refactor)
- **Removed all login**: deleted 5 files (AuthProvider, login_webview, user_profile, user_model, user_api_service), removed `webview_flutter` dependency
- **Fixed proxy system**: rewrote `ProxyConfig.createClient()`, `ImageApiClient.httpGet()` creates fresh client per request (no caching), all 3 API clients use `httpGet()`
- **Quick tags**: `RecentTagsNotifier` (SharedPreferences, max 20), displayed as `InputChip`s in search empty state
- **Fixed downloads blue AppBar**: removed hardcoded `Color.fromARGB(255, 53, 177, 239)`
- **Multi-theme**: Pure Black theme added, Follow System option, selector in drawer + settings dialog
- **Rewrote full-image screen**: SliverAppBar with aspect-ratio-aware image, card-based info layout, proper spacing, Pix-EzViewer-inspired design
- **Detailed logging**: Logger.root configured, ProxyConfig/ApiClient/YandeApi all log with timing

## Files Changed in Session 5

### Deleted
- `lib/providers/auth_provider.dart`
- `lib/utils/login_webview_page.dart`
- `lib/pages/user_profile_page.dart`
- `lib/models/user_model.dart`
- `lib/services/user_api_service.dart`
- `lib/utils/proxy_config.dart` (old — replaced by services/proxy_config.dart)

### Created
- `lib/providers/recent_tags_notifier.dart`
- `lib/services/proxy_config.dart` (rewrite with logging + testConnection)

### Rewritten
- `lib/api/image_api_client.dart` — httpGet() creates client per request, detailed logging
- `lib/api/yande_api.dart` — proxy-aware, proper client cleanup, logging
- `lib/utils/proxy_settings_page.dart` — Test button, pass/fail indicator
- `lib/utils/settings_page.dart` — theme dialog picker
- `lib/widgets/android/android_full_image_screen.dart` — complete redesign
- `lib/main.dart` — removed AuthProvider, added RecentTagsNotifier, logger setup, startup proxy test

### Edited
- `lib/widgets/common/download_images_display_widget.dart` — removed hardcoded blue AppBar
- `lib/api/danbooru_api_client.dart` — http.get → httpGet
- `lib/api/yandere_api_client.dart` — http.get → httpGet
- `lib/api/zerochan_api_client.dart` — http.get → httpGet
- `lib/pages/search_page.dart` — recent tags, saves tag on search
- `lib/widgets/drawer_widget.dart` — theme ExpansionTile, removed auth
- `pubspec.yaml` — removed `webview_flutter`

## Pending Tasks
- [x] Per-site API key/username config in settings (`SettingsPage` → `Site Account & API Key`)
- [x] Danbooru API v2 top-level + `media_asset.variants` & ISO-8601 timestamp parsing
- [x] Zerochan `www.zerochan.net` host, tolerant JSON wrapper extraction, `List` tags & JPEG preview/sample derivation
- [x] Safe mode tag filtering (`rating:s` / `rating:general`), Drawer site switch callback, and Windows Search & tag click navigation

## Session 7 — Lint zero, API hardening, Group posts, Modern loaders, Android upgrades

### Build Config Upgrades
- **Gradle**: 8.11.1 → 8.14.5 (Chinese mirror)
- **AGP**: 8.9.1 → 8.11.1
- **Kotlin**: 2.1.0 → 2.2.20 (in `settings.gradle`), removed `kotlin-android` from `app/build.gradle` (migrated to Flutter built-in Kotlin)

### Lint: 28 info hints → 0
- `use_super_parameters`: Danbooru/Yandere/Zerochan clients converted to super params
- `curly_braces_in_flow_control_structures`: android_page, windows_page
- `use_build_context_synchronously`: captured ScaffoldMessenger before async gap in download_images_display_widget
- `deprecated_member_use`: RadioListTile `groupValue`/`onChanged` → RadioGroup widget in settings_page and drawer_widget
- `prefer_const_constructors` / `prefer_const_literals`: app_theme.dart (PageTransitionsTheme, TextStyle)
- `prefer_iterable_wheretype`: danbooru_api_client

### API Parsing Hardening
- Added `resolveScore()` utility in `ImageApiClient` — handles both `int` and `Map<String, dynamic>` score values
- All 3 API clients now use `resolveScore(json['score'])` instead of `resolveInt(score['up'])`
- Per-post try-catch in `searchPosts()` of all 3 clients — logs which post failed (by id) instead of aborting entire batch

### Group/Variant Posts (图组)
- New `GroupPostsScreen` (`widgets/common/group_posts_screen.dart`)
- When a grid item has `has_children: true`, tapping opens GroupPostsScreen instead of full image
- Shows parent + all children in a masonry grid with "Parent" badge
- Tapping any variant opens its full image view
- Updated: android_page, windows_page, search_page, FavoriteDisplayWidget (both platforms)

### Modern Loading Animations
- New `sakura_loader.dart` with 3 widgets:
  - `SakuraLoader` — shimmer rectangle with optional label (replaces `CircularProgressIndicator()`)
  - `SakuraGridShimmer` — shimmer masonry grid placeholder (replaces grid loading spinner)
  - `SakuraProgressIndicator` — shimmer bar for indeterminate, `LinearProgressIndicator` for determinate
- Replaced all `CircularProgressIndicator()` instances across all screens
- Progress indicators WITH value (download progress) kept as-is (they show useful info)
- GroupPostsScreen uses `_ShimmerLoader` (inline)

## Known Issues / Gotchas
- `RadioListTile` `groupValue`/`onChanged` — FIXED (migrated to RadioGroup)
- External plugin Kotlin warnings: `file_picker`, `flutter_downloader`, `photo_manager` apply KGP — these are external plugin issues, not fixable locally
- `score` field in Danbooru API may be `int` or `Map{"up": int, "down": int, "total": int}` — handled by `resolveScore()`
- Yande.re proxy works; Danbooru/Zerochan proxy returns HTTP 200 but may fail in JSON parsing — added per-post error logging

## Known Issues / Gotchas
- `RadioListTile` `groupValue`/`onChanged` deprecated in Flutter 3.32+ — use `RadioGroup` instead (info-level only)
- `yande_api.dart`'s `fetchPosts()`, `fetchPostDetails()`, `voteForPost()`, `fetchFavoritedUsers()` were removed — only `fetchChildPosts()` remains
- `ImageApiClient.close()` is a no-op (clients created per-request and closed in finally)
- Yande.re's rating score system in `getPostDetail` might need `score` field handling
- If proxy address has full-width colon `：` (U+FF1A) instead of ASCII `:` (U+003A), `contains(':')` will fail → falls back to DIRECT (logging will show this)

## Critical Code Paths

### Proxy + API call flow
```
search_page._search()
  → siteConfig.apiClient.searchPosts(tags, page, limit)
    → YandereApiClient.searchPosts()
      → httpGet(uri)              ← ImageApiClient
        → ProxyConfig.createClient()  ← reads SharedPreferences
          → IOClient(HttpClient with findProxy = "PROXY 127.0.0.1:7897")
        → client.get(uri, headers)
        → client.close()
      ← List<PostHiveModel>
  ← update UI with results
```

### Theme switch flow
```
drawer/settings → ThemeProvider.setVariant(v)
  → SharedPreferences.setString('theme_variant', 'pureBlack')
  → notifyListeners()
  → MaterialApp rebuilds with new theme/darkTheme/themeMode
  → App rebuilds with new ThemeData
```

## API Documentation Reference

### Danbooru
- Base: `https://danbooru.donmai.us`
- Search: `GET /posts.json?tags=...&page=...&limit=...` — max limit 200
- Detail: `GET /posts/{id}.json`
- Tags: `GET /tags.json?search[name_matches]=foo*`
- Auth: `login` + `api_key` query params or HTTP Basic Auth
- Rate limit: 10 req/s global for reads
- User-Agent: recommended `YourBot/1.0 (your-username)`
- Custom status codes: 420 (invalid), 421/429 (throttled), 422 (locked), 423 (exists)
- Docs: `https://danbooru.donmai.us/wiki_pages/help:api`

### Yande.re (Moebooru API)
- Base: `https://yande.re`
- Search: `GET /post.json?tags=...&page=...&limit=...` — max limit 100
- Detail: `GET /post.json?tags=id:{id}&limit=1`
- Tags: `GET /tag.json?name_pattern=foo&limit=20` or `?name=exact`
- Auth for reads: none needed. For writes: `login` + SHA1(`choujin-steiner--{password}--`) as `password_hash`
- Docs: `https://yande.re/help/api`

### Zerochan
- Base: `https://zerochan.net`
- **URL tag path** (NOT query param): `/{tag1},{tag2}?json` — tags in URL path, comma-separated
- List all: `/?p=1&l=40&json`
- Filter by tag: `/Tag+Name?json&p=1&l=40` (spaces → `+`)
- Multiple tags: `/Tag1,Tag2?json&p=1&l=40`
- Strict mode: `/Tag?json&strict`
- Post detail: `/{id}?json` — returns single object `{ id, tags, full, thumb, ... }`
- Params: `p` (page), `l` (1-250 limit), `s` (id|fav sort), `t` (0|1|2 time)
- **Rate limit: 60 req/min**
- User-Agent **required**: `"ProjectName - Username"` — without it may be banned
- Tag suggest: `GET /suggest?q=foo`

## Directory Structure
```
lib/
├── api/
│   ├── image_api_client.dart        ← abstract base, httpGet()
│   ├── danbooru_api_client.dart     ← extends ImageApiClient
│   ├── yandere_api_client.dart      ← extends ImageApiClient
│   ├── zerochan_api_client.dart     ← extends ImageApiClient
│   ├── api_client_factory.dart      ← switch on ImageSite
│   └── yande_api.dart               ← static util (child posts only)
├── core/theme/
│   └── app_theme.dart               ← lightTheme, darkTheme, pureBlackTheme
├── exceptions/
│   └── api_exception.dart
├── models/
│   ├── post_hive_model.dart         ← Hive-able post model
│   └── site_config.dart             ← ImageSite enum, SiteConfig data class
├── pages/
│   ├── android_page.dart            ← main Android page (4-tab layout)
│   ├── windows_page.dart            ← main Windows page
│   └── search_page.dart             ← tag search + recent tags
├── providers/
│   ├── site_config_provider.dart    ← current site + safe mode
│   ├── theme_provider.dart          ← ThemeVariant enum + persistence
│   ├── favorites_notifier.dart      ← Hive-backed favorites
│   ├── recent_tags_notifier.dart    ← SharedPreferences recent tags
│   ├── base_download_notifier.dart  ← abstract download logic
│   ├── android_download_notifier.dart
│   └── windows_download_notifier.dart
├── services/
│   ├── proxy_config.dart            ← createClient() + testConnection()
│   └── download_manager.dart        ← file download management
├── utils/
│   ├── settings_page.dart           ← settings (appearance, network, about)
│   ├── proxy_settings_page.dart     ← proxy address + test button
│   └── download_settings_page.dart
└── widgets/
    ├── drawer_widget.dart
    ├── android/
    │   └── android_full_image_screen.dart
    ├── windows/
    │   └── window_full_image_screen.dart
    └── common/
        ├── download_images_display_widget.dart
        ├── group_posts_screen.dart
        └── sakura_loader.dart
```
