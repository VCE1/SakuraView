import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/core/theme/app_theme.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/pages/about_page.dart';
import 'package:vce1_sakuraview/pages/site_accounts_page.dart';
import 'package:vce1_sakuraview/pages/source_management_page.dart';
import 'package:vce1_sakuraview/providers/settings_provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/utils/download_settings_page.dart';
import 'package:vce1_sakuraview/utils/proxy_settings_page.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

/// 规范化设置页：遵循 Less is More，按「内容与显示 / 浏览与加载 / 外观 / 图源与网络 / 系统」分层归类。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeProvider = context.watch<ThemeProvider>();
    final siteProvider = context.watch<SiteConfigProvider>();
    final settingsProvider = SettingsProvider.maybeOf(context);

    final showGroupBadge = settingsProvider?.showGroupBadge ?? true;
    final showR18Badge = settingsProvider?.showR18Badge ?? true;
    final preloadImages = settingsProvider?.preloadImages ?? true;
    final viewOriginalByDefault =
        settingsProvider?.viewOriginalByDefault ?? false;
    final gridSizePreset =
        settingsProvider?.gridSizePreset ?? GridSizePreset.standard;
    final floatingNavMode =
        settingsProvider?.floatingNavMode ?? FloatingNavMode.auto;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('设置'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: <Widget>[
          _buildSectionHeader(context, '内容与显示'),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '内容分级筛选',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: RatingFilterMode.values.map((mode) {
                          return ChoiceChip(
                            label: Text(mode.displayLabel),
                            selected: siteProvider.ratingFilter == mode,
                            onSelected: (selected) {
                              if (selected) {
                                siteProvider.setRatingFilter(mode);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  secondary: const Icon(Icons.explicit_outlined, size: 22),
                  title: const Text('显示 R18 标记'),
                  value: showR18Badge,
                  onChanged: (val) => settingsProvider?.setShowR18Badge(val),
                  dense: true,
                ),
                const Divider(height: 1, indent: 48),
                SwitchListTile(
                  secondary: const Icon(Icons.photo_library_outlined, size: 22),
                  title: const Text('显示图组标记'),
                  value: showGroupBadge,
                  onChanged: (val) => settingsProvider?.setShowGroupBadge(val),
                  dense: true,
                ),
                const Divider(height: 1, indent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '预览卡片尺寸',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: GridSizePreset.values.map((preset) {
                          return ChoiceChip(
                            label: Text(preset.label),
                            selected: gridSizePreset == preset,
                            onSelected: (selected) {
                              if (selected) {
                                settingsProvider?.setGridSizePreset(preset);
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '首页底部悬浮栏',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: FloatingNavMode.values.map((mode) {
                          return ChoiceChip(
                            label: Text(mode.label),
                            selected: floatingNavMode == mode,
                            onSelected: (selected) {
                              if (selected) {
                                settingsProvider?.setFloatingNavMode(mode);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          _buildSectionHeader(context, '浏览与加载'),
          _SettingsCard(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.hd_outlined, size: 22),
                  title: const Text('查看图片默认加载原图 (HD)'),
                  value: viewOriginalByDefault,
                  onChanged: (val) =>
                      settingsProvider?.setViewOriginalByDefault(val),
                  dense: true,
                ),
                const Divider(height: 1, indent: 48),
                SwitchListTile(
                  secondary: const Icon(Icons.bolt_rounded, size: 22),
                  title: const Text('预加载图片'),
                  value: preloadImages,
                  onChanged: (val) => settingsProvider?.setPreloadImages(val),
                  dense: true,
                ),
              ],
            ),
          ),

          _buildSectionHeader(context, '外观'),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模式',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ThemeVariant.values.map((v) {
                      return ChoiceChip(
                        label: Text(v.label),
                        selected: themeProvider.variant == v,
                        onSelected: (val) {
                          if (val) themeProvider.setVariant(v);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Text(
                    '配色',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SakuraColorSeed.values.map((seed) {
                      return ChoiceChip(
                        label: Text(seed.label),
                        selected: themeProvider.colorSeed == seed,
                        avatar: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: seed.seedColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        onSelected: (val) {
                          if (val) themeProvider.setColorSeed(seed);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          _buildSectionHeader(context, '图源与网络'),
          _SettingsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.hub_outlined, size: 22),
                  title: const Text('图源管理'),
                  subtitle: Text(
                    '当前：${siteProvider.currentSource.name} · ${siteProvider.enabledSources.length}/${siteProvider.allSources.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  dense: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SourceManagementPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 48),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined, size: 22),
                  title: const Text('站点账号'),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  dense: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SiteAccountsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 48),
                ListTile(
                  leading: const Icon(Icons.router_outlined, size: 22),
                  title: const Text('网络代理'),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  dense: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProxySettingsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 48),
                ListTile(
                  leading: const Icon(Icons.tune_rounded, size: 22),
                  title: const Text('下载设置'),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  dense: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DownloadSettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          _buildSectionHeader(context, '系统'),
          _SettingsCard(
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded, size: 22),
              title: const Text('关于'),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              dense: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AboutPage(),
                  ),
                );
              },
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      margin: const EdgeInsets.only(top: 6, bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
