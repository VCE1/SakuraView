import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/models/site_config.dart';

class AppDrawer extends StatefulWidget {
  final bool isSafeMode;
  final Function(bool) onSafeModeChanged;
  final ValueChanged<ImageSite>? onSiteChanged;
  final Function() onHomeTapped;
  final Function() onFavoritesTapped;
  final Function() onDownloadsTapped;
  final Function() onSearchTapped;
  final Function() onHistoryTapped;
  final Function() onFollowTapped;
  final Function() onRankingTapped;
  final Function() onSettingsTapped;

  const AppDrawer({
    super.key,
    required this.isSafeMode,
    required this.onHomeTapped,
    required this.onSafeModeChanged,
    this.onSiteChanged,
    required this.onFavoritesTapped,
    required this.onDownloadsTapped,
    required this.onSearchTapped,
    required this.onHistoryTapped,
    required this.onFollowTapped,
    required this.onRankingTapped,
    required this.onSettingsTapped,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: Column(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white.withAlpha(60),
                      child: const Icon(
                        Icons.local_florist,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SakuraView',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Anime Image Viewer',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomRight: Radius.circular(24),
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _DrawerTile(
                    icon: Icons.home_outlined,
                    title: 'Home',
                    onTap: widget.onHomeTapped,
                  ),
                  _DrawerTile(
                    icon: Icons.favorite_outline,
                    title: 'Favorites',
                    onTap: widget.onFavoritesTapped,
                  ),
                  _DrawerTile(
                    icon: Icons.download_outlined,
                    title: 'Downloads',
                    onTap: widget.onDownloadsTapped,
                  ),
                  _DrawerTile(
                    icon: Icons.search,
                    title: 'Search',
                    onTap: widget.onSearchTapped,
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  Consumer<SiteConfigProvider>(
                    builder: (context, siteConfig, child) {
                      return ExpansionTile(
                        leading: const Icon(Icons.cloud_outlined),
                        title: const Text('Image Site'),
                        subtitle: Text(
                          siteConfig.config.site.displayName,
                          style: const TextStyle(fontSize: 12),
                        ),
                        initiallyExpanded: false,
                        childrenPadding: EdgeInsets.zero,
                        children: [
                          RadioGroup<ImageSite>(
                            groupValue: siteConfig.config.site,
                            onChanged: (value) {
                              if (value != null) {
                                Navigator.pop(context);
                                if (widget.onSiteChanged != null) {
                                  widget.onSiteChanged!(value);
                                } else {
                                  siteConfig.setSite(value);
                                }
                              }
                            },
                            child: Column(
                              children: ImageSite.values.map((site) {
                                return RadioListTile<ImageSite>(
                                  title: Text(site.displayName),
                                  value: site,
                                  dense: true,
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  Consumer<SiteConfigProvider>(
                    builder: (context, siteConfig, child) {
                      return SwitchListTile(
                        title: const Text('Safe Mode'),
                        value: siteConfig.config.safeMode,
                        onChanged: (bool value) {
                          widget.onSafeModeChanged(value);
                        },
                        secondary: const Icon(Icons.shield_outlined),
                        dense: true,
                      );
                    },
                  ),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, child) {
                      return ExpansionTile(
                        leading: Icon(
                          themeProvider.isDarkMode
                              ? Icons.dark_mode
                              : Icons.light_mode,
                        ),
                        title: const Text('Theme'),
                        subtitle: Text(themeProvider.variant.label),
                        initiallyExpanded: false,
                        childrenPadding: EdgeInsets.zero,
                        children: [
                          RadioGroup<ThemeVariant>(
                            groupValue: themeProvider.variant,
                            onChanged: (value) {
                              if (value != null) {
                                Navigator.pop(context);
                                themeProvider.setVariant(value);
                              }
                            },
                            child: Column(
                              children: ThemeVariant.values.map((v) {
                                return RadioListTile<ThemeVariant>(
                                  title: Text(v.label),
                                  value: v,
                                  dense: true,
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    onTap: widget.onSettingsTapped,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
    );
  }
}
