import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/core/theme/app_theme.dart';
import 'package:vce1_sakuraview/pages/about_page.dart';
import 'package:vce1_sakuraview/pages/site_accounts_page.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/utils/download_settings_page.dart';
import 'package:vce1_sakuraview/utils/proxy_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeProvider = context.watch<ThemeProvider>();
    final siteProvider = context.watch<SiteConfigProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('系统设置', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: <Widget>[
          // Section 1: Appearance & Theme
          _buildSectionHeader(context, '界面与外观', Icons.palette_outlined),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主题显示模式',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ThemeVariant.values.map((v) {
                      final isSelected = themeProvider.variant == v;
                      return ChoiceChip(
                        label: Text(v.label),
                        selected: isSelected,
                        onSelected: (val) {
                          if (val) themeProvider.setVariant(v);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    '主题强调色 (Material 3 Seed)',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: SakuraColorSeed.values.map((seed) {
                      final isSelected = themeProvider.colorSeed == seed;
                      return InkWell(
                        onTap: () => themeProvider.setColorSeed(seed),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? seed.seedColor.withValues(alpha: 0.2)
                                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isSelected ? seed.seedColor : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: seed.seedColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                seed.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? seed.seedColor : cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          // Section 2: Accounts & Sites
          _buildSectionHeader(context, '站点账户与会话', Icons.account_circle_outlined),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.badge_outlined, color: cs.primary),
                  title: const Text('多站点账户管理与网页登录'),
                  subtitle: Text(
                    '独立配置 Danbooru、Yande.re、Zerochan 凭据、Cookie 与 User-Agent',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SiteAccountsPage(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: Icon(Icons.security_outlined, color: cs.primary),
                  title: const Text('安全模式 (Safe Mode)'),
                  subtitle: const Text('自动过滤成人与敏感级内容 (Rating: e/q)'),
                  value: siteProvider.config.safeMode,
                  onChanged: (val) {
                    siteProvider.setSafeMode(val);
                  },
                ),
              ],
            ),
          ),

          // Section 3: Network & Proxy
          _buildSectionHeader(context, '网络与连接', Icons.hub_outlined),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            child: ListTile(
              leading: Icon(Icons.router_outlined, color: cs.primary),
              title: const Text('网络代理策略与连通性测试'),
              subtitle: const Text('跟随系统代理 / 自定义 HTTP 代理 / 直连模式'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProxySettingsPage(),
                  ),
                );
              },
            ),
          ),

          // Section 4: Downloads & Storage
          _buildSectionHeader(context, '下载与存储管理', Icons.folder_open_outlined),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            child: ListTile(
              leading: Icon(Icons.file_download_outlined, color: cs.primary),
              title: const Text('下载存储位置与路径设置'),
              subtitle: const Text('公开相册 Pictures / 下载目录 / DCIM / 应用私有 / 自定义'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DownloadSettingsPage(),
                  ),
                );
              },
            ),
          ),

          // Section 5: About
          _buildSectionHeader(context, '关于与致谢', Icons.info_outline_rounded),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 24),
            child: ListTile(
              leading: Icon(Icons.filter_vintage_rounded, color: cs.primary),
              title: const Text('关于 SakuraView'),
              subtitle: const Text('感谢使用、项目架构、多站点支持与开源致谢'),
              trailing: const Icon(Icons.chevron_right_rounded),
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
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}
