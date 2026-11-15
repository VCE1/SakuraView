import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_build_info.dart';

/// 开源依赖插件元数据，名称、项目地址与官方简介均来自各依赖包的 pubspec.yaml。
class OpenSourcePackageInfo {
  final String name;
  final String url;
  final String description;

  const OpenSourcePackageInfo({
    required this.name,
    required this.url,
    required this.description,
  });
}

/// 关于页面：展示项目简介、版本与构建时间，以及各开源插件的项目地址与官方简介。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String projectDescription =
      '这是一款兴趣使然，由Flutter编写的轻量看图应用。目前支持多数booru系图站。';
  static const String closingGreeting = '感谢使用 SakuraView，请多多指教~';

  static const List<OpenSourcePackageInfo> openSourcePackages = [
    OpenSourcePackageInfo(
      name: 'cached_network_image',
      url: 'https://github.com/Baseflow/flutter_cached_network_image',
      description: 'Flutter library to load and cache network images.',
    ),
    OpenSourcePackageInfo(
      name: 'http',
      url: 'https://github.com/dart-lang/http/tree/master/pkgs/http',
      description: 'A composable, multi-platform, Future-based API for HTTP requests.',
    ),
    OpenSourcePackageInfo(
      name: 'flutter_staggered_grid_view',
      url: 'https://github.com/letsar/flutter_staggered_grid_view',
      description:
          'Provides a collection of Flutter grids layouts (staggered, masonry, quilted, woven, etc.).',
    ),
    OpenSourcePackageInfo(
      name: 'provider',
      url: 'https://github.com/rrousselGit/provider',
      description:
          'A wrapper around InheritedWidget to make them easier to use and more reusable.',
    ),
    OpenSourcePackageInfo(
      name: 'photo_view',
      url: 'https://github.com/renancaraujo/photo_view',
      description:
          'Photo View provides a gesture sensitive zoomable widget. Photo View is largely used to show interactive images and other stuff such as SVG.',
    ),
    OpenSourcePackageInfo(
      name: 'shared_preferences',
      url:
          'https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences',
      description:
          'Flutter plugin for reading and writing simple key-value pairs.',
    ),
    OpenSourcePackageInfo(
      name: 'path_provider',
      url:
          'https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider',
      description:
          'Flutter plugin for getting commonly used locations on host platform file systems, such as the temp and app data directories.',
    ),
    OpenSourcePackageInfo(
      name: 'hive',
      url: 'https://github.com/hivedb/hive/tree/master/hive',
      description:
          'Lightweight and blazing fast key-value database written in pure Dart. Strongly encrypted using AES-256.',
    ),
    OpenSourcePackageInfo(
      name: 'hive_flutter',
      url: 'https://github.com/hivedb/hive/tree/master/hive_flutter',
      description: 'Extension for Hive. Makes it easier to use Hive in Flutter apps.',
    ),
    OpenSourcePackageInfo(
      name: 'html',
      url: 'https://github.com/dart-lang/tools/tree/main/pkgs/html',
      description:
          'APIs for parsing and manipulating HTML content outside the browser.',
    ),
    OpenSourcePackageInfo(
      name: 'xml',
      url: 'https://github.com/renggli/dart-xml',
      description:
          'Full-featured XML for Dart — DOM parsing, SAX streaming, XPath 3 querying, and a fluent builder API.',
    ),
    OpenSourcePackageInfo(
      name: 'url_launcher',
      url:
          'https://github.com/flutter/packages/tree/main/packages/url_launcher/url_launcher',
      description:
          'Flutter plugin for launching a URL. Supports web, phone, SMS, and email schemes.',
    ),
    OpenSourcePackageInfo(
      name: 'share_plus',
      url:
          'https://github.com/fluttercommunity/plus_plugins/tree/main/packages/share_plus/share_plus',
      description:
          'Flutter plugin for sharing content via the platform share UI, using the ACTION_SEND intent on Android and UIActivityViewController on iOS.',
    ),
    OpenSourcePackageInfo(
      name: 'photo_manager',
      url: 'https://github.com/fluttercandies/flutter_photo_manager',
      description:
          'A Flutter plugin that provides album assets abstraction management APIs on Android, iOS, macOS, and OpenHarmony.',
    ),
    OpenSourcePackageInfo(
      name: 'file_picker',
      url: 'https://github.com/miguelpruivo/flutter_file_picker',
      description:
          'A package that allows you to use a native file explorer to pick single or multiple absolute file paths, with extension filtering support.',
    ),
    OpenSourcePackageInfo(
      name: 'shimmer',
      url: 'https://github.com/hnvn/flutter_shimmer',
      description:
          'A lightweight Flutter widget that paints a moving highlight over skeleton placeholders and call-to-action text.',
    ),
    OpenSourcePackageInfo(
      name: 'crypto',
      url: 'https://github.com/dart-lang/core/tree/main/pkgs/crypto',
      description: 'Implementations of SHA, MD5, and HMAC cryptographic functions.',
    ),
    OpenSourcePackageInfo(
      name: 'intl',
      url: 'https://github.com/dart-lang/i18n/tree/main/pkgs/intl',
      description:
          'Contains code to deal with internationalized/localized messages, date and number formatting and parsing, bi-directional text, and other internationalization issues.',
    ),
    OpenSourcePackageInfo(
      name: 'logging',
      url: 'https://github.com/dart-lang/core/tree/main/pkgs/logging',
      description:
          'Provides APIs for debugging and error logging, similar to loggers in other languages, such as the Closure JS Logger and java.util.logging.Logger.',
    ),
    OpenSourcePackageInfo(
      name: 'google_fonts',
      url:
          'https://github.com/flutter/packages/tree/main/packages/google_fonts',
      description:
          'A Flutter package to use fonts from fonts.google.com. Supports HTTP fetching, caching, and asset bundling.',
    ),
    OpenSourcePackageInfo(
      name: 'bitsdojo_window',
      url: 'https://github.com/bitsdojo/bitsdojo_window',
      description:
          'A package to help with creating custom windows with Flutter desktop (custom border, titlebar and minimize/maximize/close buttons) and common desktop window operations (show/hide/position on screen) for Windows and macOS',
    ),
    OpenSourcePackageInfo(
      name: 'path',
      url: 'https://github.com/dart-lang/core/tree/main/pkgs/path',
      description:
          'A string-based path manipulation library. All of the path operations you know and love, with solid support for Windows, POSIX (Linux and Mac OS X), and the web.',
    ),
  ];

  Future<void> _openPackageUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开链接：$url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('关于'),
      ),
      body: SelectionArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primaryContainer.withValues(alpha: 0.7),
                  colorScheme.secondaryContainer.withValues(alpha: 0.45),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.collections_rounded,
                        size: 28,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SakuraView',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '当前版本：v${AppBuildInfo.fullVersion}',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  projectDescription,
                  style: textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    children: [
                      _MetaRow(
                        label: '当前版本',
                        value: 'v${AppBuildInfo.fullVersion}',
                      ),
                      const SizedBox(height: 6),
                      const _MetaRow(
                        label: '构建时间',
                        value: AppBuildInfo.buildTime,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  closingGreeting,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '开源插件与致谢',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...openSourcePackages.map(
            (pkg) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openPackageUrl(context, pkg.url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              pkg.name,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '复制项目链接',
                            icon: Icon(
                              Icons.content_copy_rounded,
                              size: 16,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: pkg.url),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(
                                      content: Text('已复制 ${pkg.name} 链接'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                              }
                            },
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pkg.description,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pkg.url,
                        style: textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
