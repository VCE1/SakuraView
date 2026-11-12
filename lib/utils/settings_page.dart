import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/providers/theme_provider.dart';
import 'package:vce1_sakuraview/utils/proxy_settings_page.dart';
import 'package:vce1_sakuraview/utils/download_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _showThemePicker(BuildContext context, ThemeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Theme'),
        children: [
          RadioGroup<ThemeVariant>(
            groupValue: provider.variant,
            onChanged: (value) {
              if (value != null) {
                provider.setVariant(value);
                Navigator.pop(ctx);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }

  void _showSiteCredentialsDialog(
      BuildContext context, SiteConfigProvider siteProvider) {
    final userCtrl = TextEditingController(text: siteProvider.config.username);
    final keyCtrl = TextEditingController(text: siteProvider.config.apiKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Site Credentials & API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              decoration: const InputDecoration(
                labelText: 'Username (Danbooru / Zerochan UA)',
                hintText: 'e.g. vce1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key (Optional)',
                hintText: 'Danbooru API key or Zerochan token',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await siteProvider.setUsername(userCtrl.text.trim());
              await siteProvider.setApiKey(keyCtrl.text.trim());
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return ListTile(
                leading: Icon(
                  themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                ),
                title: const Text('Appearance'),
                subtitle: Text(themeProvider.variant.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showThemePicker(context, themeProvider),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud),
            title: const Text('Network'),
            subtitle: const Text('Proxy settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ProxySettingsPage(),
                ),
              );
            },
          ),
          Consumer<SiteConfigProvider>(
            builder: (context, siteProvider, child) {
              final user = siteProvider.config.username;
              return ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: const Text('Site Account & API Key'),
                subtitle: Text(
                  user.isNotEmpty
                      ? 'Username: $user'
                      : 'Configure username / API key for Danbooru & Zerochan',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showSiteCredentialsDialog(context, siteProvider),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Download'),
            subtitle: const Text('Download path and options'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DownloadSettingsPage(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: const Text('Version and info'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'SakuraView',
                applicationVersion: '1.1.0',
                applicationIcon: const Icon(Icons.local_florist,
                    color: Color(0xFFEC407A), size: 48),
                children: [
                  const Text('A multi-site anime image viewer.'),
                  const Text('Supports Danbooru, Yande.re, Zerochan.'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
