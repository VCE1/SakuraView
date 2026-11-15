import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/core/utils/post_normalization.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';

/// Clean, anti-redundant navigation drawer.
/// Strict adherence to Less is More:
/// - No verbose slogans, promotional texts or subtitles
/// - No rainbow colors or heavy gradients
/// - Flat single-level list with clear concise items
class AppDrawer extends StatelessWidget {
  final bool isSafeMode;
  final ValueChanged<bool> onSafeModeChanged;
  final RatingFilterMode? ratingFilter;
  final ValueChanged<RatingFilterMode>? onRatingFilterChanged;
  final ValueChanged<String>? onSiteChanged;
  final VoidCallback onHomeTapped;
  final VoidCallback onFavoritesTapped;
  final VoidCallback onDownloadsTapped;
  final VoidCallback onSearchTapped;
  final VoidCallback? onHistoryTapped;
  final VoidCallback? onBlacklistTapped;
  final VoidCallback? onSiteAccountsTapped;
  final VoidCallback? onSettingsTapped;
  final VoidCallback? onAboutTapped;
  final int activeIndex;

  const AppDrawer({
    super.key,
    required this.isSafeMode,
    required this.onSafeModeChanged,
    this.ratingFilter,
    this.onRatingFilterChanged,
    this.onSiteChanged,
    required this.onHomeTapped,
    required this.onFavoritesTapped,
    required this.onDownloadsTapped,
    required this.onSearchTapped,
    this.onHistoryTapped,
    this.onBlacklistTapped,
    this.onSiteAccountsTapped,
    this.onSettingsTapped,
    this.onAboutTapped,
    this.activeIndex = 0,
  });

  void _showSiteSelectionSheet(BuildContext context, SiteConfigProvider siteConfig) {
    final enabled = siteConfig.enabledSources;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '切换图站',
                      style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...enabled.map((source) {
                final isSelected = source.id == siteConfig.currentSourceId;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: isSelected ? Theme.of(sheetCtx).colorScheme.primary : null,
                  ),
                  title: Text(
                    source.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: Text(
                    source.id.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(sheetCtx).colorScheme.outline,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    if (onSiteChanged != null) {
                      onSiteChanged!(source.id);
                    } else {
                      siteConfig.setSourceById(source.id);
                    }
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final siteConfig = context.watch<SiteConfigProvider>();
    final currentSource = siteConfig.currentSource;

    return Drawer(
      child: Column(
        children: [
          // Header Area: clean surface, no heavy gradients
          Container(
            width: double.infinity,
            color: cs.surfaceContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.collections_rounded,
                            size: 17,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'SakuraView',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Current Site Selector
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _showSiteSelectionSheet(context, siteConfig),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.cloud_outlined,
                              size: 16,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                currentSource.name,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.unfold_more_rounded,
                              color: cs.outline,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          // Navigation Items: simple, flat list without clutter
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _DrawerNavTile(
                  icon: Icons.explore_outlined,
                  title: '发现',
                  isSelected: activeIndex == 0,
                  onTap: () {
                    Navigator.pop(context);
                    onHomeTapped();
                  },
                ),
                _DrawerNavTile(
                  icon: Icons.search_rounded,
                  title: '搜索',
                  isSelected: activeIndex == 1,
                  onTap: () {
                    Navigator.pop(context);
                    onSearchTapped();
                  },
                ),
                _DrawerNavTile(
                  icon: Icons.favorite_outline_rounded,
                  title: '收藏',
                  isSelected: activeIndex == 2,
                  onTap: () {
                    Navigator.pop(context);
                    onFavoritesTapped();
                  },
                ),
                _DrawerNavTile(
                  icon: Icons.download_outlined,
                  title: '下载',
                  isSelected: false,
                  onTap: () {
                    Navigator.pop(context);
                    onDownloadsTapped();
                  },
                ),
                _DrawerNavTile(
                  icon: Icons.history_rounded,
                  title: '历史',
                  isSelected: false,
                  onTap: () {
                    Navigator.pop(context);
                    onHistoryTapped?.call();
                  },
                ),
                _DrawerNavTile(
                  icon: Icons.block_rounded,
                  title: '黑名单',
                  isSelected: false,
                  onTap: () {
                    Navigator.pop(context);
                    onBlacklistTapped?.call();
                  },
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Divider(height: 1),
                ),

                Builder(
                  builder: (context) {
                    final activeMode = ratingFilter ??
                        (isSafeMode
                            ? RatingFilterMode.safe
                            : RatingFilterMode.all);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                activeMode.isR18Only
                                    ? Icons.explicit_rounded
                                    : (activeMode.isSafe
                                        ? Icons.shield_outlined
                                        : Icons.layers_outlined),
                                size: 20,
                                color: activeMode.isR18Only
                                    ? cs.error
                                    : (activeMode.isSafe
                                        ? cs.primary
                                        : cs.onSurfaceVariant),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '内容筛选',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: RatingFilterMode.values.map((mode) {
                              final selected = activeMode == mode;
                              return ChoiceChip(
                                label: Text(
                                  mode.shortLabel,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                selected: selected,
                                visualDensity: VisualDensity.compact,
                                onSelected: (_) {
                                  if (onRatingFilterChanged != null) {
                                    onRatingFilterChanged!(mode);
                                  } else {
                                    onSafeModeChanged(mode.isSafe);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                _DrawerNavTile(
                  icon: Icons.manage_accounts_outlined,
                  title: '账号',
                  isSelected: false,
                  onTap: () {
                    Navigator.pop(context);
                    onSiteAccountsTapped?.call();
                  },
                ),
                _DrawerNavTile(
                  icon: Icons.settings_outlined,
                  title: '设置',
                  isSelected: false,
                  onTap: () {
                    Navigator.pop(context);
                    onSettingsTapped?.call();
                  },
                ),
                _DrawerNavTile(
                  icon: Icons.info_outline_rounded,
                  title: '关于',
                  isSelected: false,
                  onTap: () {
                    Navigator.pop(context);
                    onAboutTapped?.call();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerNavTile({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        selected: isSelected,
        selectedTileColor: cs.primaryContainer.withValues(alpha: 0.35),
        selectedColor: cs.primary,
        leading: Icon(icon, size: 22),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        dense: true,
        onTap: onTap,
      ),
    );
  }
}
