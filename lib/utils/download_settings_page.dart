import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vce1_sakuraview/providers/base_download_notifier.dart';
import 'package:vce1_sakuraview/utils/settings_service.dart';

class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  final TextEditingController _customPathController = TextEditingController();
  final SettingsService _settingsService = SettingsService();

  DownloadStoragePreset _selectedPreset = DownloadStoragePreset.publicPictures;
  Map<DownloadStoragePreset, String> _resolvedPaths = {};
  String _activePath = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final preset = await _settingsService.getDownloadPreset();
    final savedPath = await _settingsService.getDownloadPath();

    final Map<DownloadStoragePreset, String> paths = {};
    for (final p in DownloadStoragePreset.values) {
      if (p == DownloadStoragePreset.custom) {
        paths[p] = savedPath ?? '';
      } else {
        paths[p] = await _settingsService.resolvePathForPreset(p);
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedPreset = preset;
      _resolvedPaths = paths;
      _activePath = savedPath ?? paths[preset] ?? '';
      _customPathController.text = _activePath;
      _isLoading = false;
    });
  }

  Future<void> _selectPreset(DownloadStoragePreset preset) async {
    if (preset == DownloadStoragePreset.custom) {
      setState(() {
        _selectedPreset = preset;
      });
      return;
    }

    await _settingsService.setDownloadPreset(preset);
    final newPath = await _settingsService.getDownloadPath() ?? '';
    if (!mounted) return;
    setState(() {
      _selectedPreset = preset;
      _activePath = newPath;
      _customPathController.text = newPath;
    });

    try {
      await context.read<BaseDownloadNotifier>().scanForDownloadedImages();
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换下载位置：${preset.title}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _pickCustomFolder() async {
    String? selectedDirectory;
    try {
      selectedDirectory = await FilePicker.getDirectoryPath();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开系统文件夹选择器失败: $e')),
        );
      }
      return;
    }

    if (selectedDirectory != null && selectedDirectory.trim().isNotEmpty) {
      await _settingsService.setDownloadPreset(
        DownloadStoragePreset.custom,
        customPath: selectedDirectory.trim(),
      );
      final resolved = await _settingsService.getDownloadPath() ?? selectedDirectory.trim();
      if (!mounted) return;
      setState(() {
        _selectedPreset = DownloadStoragePreset.custom;
        _activePath = resolved;
        _customPathController.text = resolved;
        _resolvedPaths[DownloadStoragePreset.custom] = resolved;
      });
      try {
        await context.read<BaseDownloadNotifier>().scanForDownloadedImages();
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已设置自定义下载路径：$resolved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _saveCustomPathText() async {
    final text = _customPathController.text.trim();
    if (text.isEmpty) return;
    await _settingsService.setDownloadPreset(
      DownloadStoragePreset.custom,
      customPath: text,
    );
    final resolved = await _settingsService.getDownloadPath() ?? text;
    if (!mounted) return;
    setState(() {
      _selectedPreset = DownloadStoragePreset.custom;
      _activePath = resolved;
      _customPathController.text = resolved;
    });
    try {
      await context.read<BaseDownloadNotifier>().scanForDownloadedImages();
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存下载路径：$resolved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _customPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('下载存储与路径管理')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final presets = Platform.isAndroid
        ? DownloadStoragePreset.values
        : [
            DownloadStoragePreset.publicDownloads,
            DownloadStoragePreset.appPrivate,
            DownloadStoragePreset.custom,
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载存储与路径管理'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active Path Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.folder_special_rounded, color: cs.primary, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '当前生效存储路径',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedPreset.isPublicStorage
                                  ? cs.primary.withValues(alpha: 0.15)
                                  : cs.tertiary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _selectedPreset.isPublicStorage ? '公开目录' : '隔离/自定义',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _selectedPreset.isPublicStorage
                                    ? cs.primary
                                    : cs.tertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        _activePath,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Preset Radio Cards
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RadioGroup<DownloadStoragePreset>(
                groupValue: _selectedPreset,
                onChanged: (val) {
                  if (val != null) {
                    _selectPreset(val);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        '选择存储位置类型',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...presets.map((preset) {
                      final resolved = _resolvedPaths[preset] ?? '';
                      return RadioListTile<DownloadStoragePreset>(
                        value: preset,
                        title: Text(
                          preset.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              preset.subtitle,
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (resolved.isNotEmpty &&
                                preset != DownloadStoragePreset.custom) ...[
                              const SizedBox(height: 4),
                              Text(
                                resolved,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Custom Directory Picker Section
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '自定义文件夹路径',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '您可以通过系统文件选择器指定任意文件夹，或直接输入目标目录完整路径：',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customPathController,
                    decoration: InputDecoration(
                      labelText: '文件夹路径',
                      hintText: '/storage/emulated/0/Pictures/SakuraView',
                      prefixIcon: const Icon(Icons.folder_outlined),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.folder_open_rounded),
                        tooltip: '浏览并选择文件夹',
                        onPressed: _pickCustomFolder,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickCustomFolder,
                          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                          label: const Text('从系统选择器浏览'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saveCustomPathText,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('保存当前路径'),
                        ),
                      ),
                    ],
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
