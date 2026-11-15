import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:vce1_sakuraview/core/sources/source_models.dart';
import 'package:vce1_sakuraview/providers/recent_tags_notifier.dart';
import 'package:vce1_sakuraview/providers/site_config_provider.dart';
import 'package:vce1_sakuraview/services/blacklist_service.dart';
import 'package:vce1_sakuraview/services/followed_tags_service.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_page_route.dart';
import 'package:vce1_sakuraview/widgets/common/search_results_page.dart';
import 'package:vce1_sakuraview/widgets/common/tag_action_sheet.dart';

/// 搜索主入口页：负责标签联想补全、多条件高级筛选、最近历史与快速搜索预设。
///
/// 提交检索或点击历史标签时会以独立路由压入 [SearchResultsPage]，从而保证
/// 任意层级返回时必然先回到本搜索页（且输入法保持收起），绝不直接跳回主页。
class SearchPage extends StatefulWidget {
  final String? initialTag;
  final String? initialQuery;

  const SearchPage({
    super.key,
    this.initialTag,
    this.initialQuery,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _uploaderController = TextEditingController();
  final TextEditingController _artistController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _uploaderFocusNode = FocusNode();
  final FocusNode _artistFocusNode = FocusNode();

  List<TagSuggestion> _suggestions = const [];
  Timer? _suggestDebounce;
  bool _isSuggestLoading = false;
  bool _showFilters = false;
  String? _selectedSort;

  // 若旧调用方以 `SearchPage(initialQuery: ...)` 直接传入初始词，保留内嵌结果视图兼容
  String? _inlineQuery;
  String _inlineUploader = '';
  String _inlineArtist = '';
  String? _inlineSort;

  @override
  void initState() {
    super.initState();
    final incoming = (widget.initialQuery ?? widget.initialTag)?.trim();
    if (incoming != null && incoming.isNotEmpty) {
      _searchController.text = incoming;
      _inlineQuery = incoming;
    }
  }

  @override
  void didUpdateWidget(SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = (widget.initialQuery ?? widget.initialTag)?.trim();
    final previous = (oldWidget.initialQuery ?? oldWidget.initialTag)?.trim();
    if (incoming != null && incoming != previous && incoming.isNotEmpty) {
      _searchController.text = incoming;
      setState(() {
        _inlineQuery = incoming;
        _suggestions = const [];
      });
    }
  }

  void _unfocusAll() {
    _searchFocusNode.unfocus();
    _uploaderFocusNode.unfocus();
    _artistFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchController.dispose();
    _uploaderController.dispose();
    _artistController.dispose();
    _searchFocusNode.dispose();
    _uploaderFocusNode.dispose();
    _artistFocusNode.dispose();
    super.dispose();
  }

  String _currentEditingToken(String text) {
    final trimmedLeft = text.trimLeft();
    if (trimmedLeft.isEmpty || text.endsWith(' ')) return '';
    final parts = text.split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.last.trim() : '';
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _suggestDebounce?.cancel();
    final token = _currentEditingToken(value);
    if (token.isEmpty) {
      if (_suggestions.isNotEmpty) {
        setState(() {
          _suggestions = const [];
          _isSuggestLoading = false;
        });
      }
      return;
    }

    final siteConfig = context.read<SiteConfigProvider>();
    if (!siteConfig.currentSource.capabilities.supportsTagAutocomplete) {
      return;
    }

    _suggestDebounce = Timer(const Duration(milliseconds: 280), () async {
      if (!mounted) return;
      setState(() => _isSuggestLoading = true);
      try {
        final suggestions = await siteConfig.apiClient.suggestTags(token);
        if (!mounted) return;
        if (_currentEditingToken(_searchController.text) == token) {
          setState(() {
            _suggestions = suggestions;
            _isSuggestLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSuggestLoading = false);
      }
    });
  }

  void _acceptSuggestion(TagSuggestion suggestion) {
    final text = _searchController.text;
    final lastSpace = text.lastIndexOf(RegExp(r'\s'));
    final prefix = lastSpace >= 0 ? text.substring(0, lastSpace + 1) : '';
    final nextText = '$prefix${suggestion.value} ';
    _searchController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    setState(() => _suggestions = const []);
  }

  Future<void> _submitSearch({
    String? overrideQuery,
    String? overrideUploader,
    String? overrideArtist,
    String? overrideSort,
  }) async {
    final query = (overrideQuery ?? _searchController.text).trim();
    final uploader = (overrideUploader ?? _uploaderController.text).trim();
    final artist = (overrideArtist ?? _artistController.text).trim();
    final sort = overrideSort ?? _selectedSort;
    if (query.isEmpty && uploader.isEmpty && artist.isEmpty) return;

    _unfocusAll();
    if (_suggestions.isNotEmpty) {
      setState(() => _suggestions = const []);
    }

    if (query.isNotEmpty) {
      _searchController.text = query;
      await context.read<RecentTagsNotifier>().addTag(query);
    }

    if (!mounted) return;

    if (widget.initialQuery != null || widget.initialTag != null) {
      setState(() {
        _inlineQuery = query;
        _inlineUploader = uploader;
        _inlineArtist = artist;
        _inlineSort = sort;
      });
      return;
    }

    await Navigator.of(context).push(
      SakuraPageRoute(
        builder: (_) => SearchResultsPage(
          query: query,
          uploader: uploader,
          artist: artist,
          sort: sort,
        ),
      ),
    );
    if (mounted) {
      _unfocusAll();
    }
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'artist':
        return '画师';
      case 'character':
        return '角色';
      case 'copyright':
        return '原作';
      case 'meta':
        return '元标签';
      default:
        return '标签';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final siteConfig = context.watch<SiteConfigProvider>();
    final caps = siteConfig.currentSource.capabilities;
    final hasActiveFilters = _uploaderController.text.trim().isNotEmpty ||
        _artistController.text.trim().isNotEmpty ||
        (_selectedSort != null && _selectedSort!.isNotEmpty);

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_suggestions.isNotEmpty) {
          setState(() => _suggestions = const []);
        }
        _unfocusAll();
      },
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              isLandscape ? 4 : 8,
              16,
              isLandscape ? 4 : 6,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: isLandscape ? 42 : 46,
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              style: TextStyle(fontSize: isLandscape ? 13.5 : 14.5),
                              decoration: InputDecoration(
                                hintText: '搜索标签（输入自动联想）',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 0,
                                ),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isSuggestLoading)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.8,
                                          ),
                                        ),
                                      ),
                                    if (_searchController.text.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _suggestions = const [];
                                            _inlineQuery = null;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                                filled: true,
                                fillColor: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.6),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              textInputAction: TextInputAction.search,
                              onChanged: _onQueryChanged,
                              onSubmitted: (_) => _submitSearch(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: _submitSearch,
                          child: const Text('搜索'),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: '高级筛选',
                          style: IconButton.styleFrom(
                            backgroundColor: (_showFilters || hasActiveFilters)
                                ? cs.primaryContainer
                                : cs.surfaceContainerHighest.withValues(alpha: 0.65),
                            foregroundColor: (_showFilters || hasActiveFilters)
                                ? cs.onPrimaryContainer
                                : cs.onSurface,
                          ),
                          icon: Icon(
                            hasActiveFilters
                                ? Icons.filter_alt_rounded
                                : Icons.tune_rounded,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() => _showFilters = !_showFilters);
                          },
                        ),
                      ],
                    ),
                    if (_showFilters) ...[
                      const SizedBox(height: 8),
                      _buildFilterPanel(context, caps),
                    ],
                    if (_suggestions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildSuggestionsPanel(context),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _inlineQuery != null && _inlineQuery!.isNotEmpty
                ? SearchResultsView(
                    query: _inlineQuery!,
                    uploader: _inlineUploader,
                    artist: _inlineArtist,
                    sort: _inlineSort,
                    bottomPadding: 86,
                  )
                  : _buildSearchHub(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPanel(BuildContext context, SourceCapabilities caps) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _artistController,
                  focusNode: _artistFocusNode,
                  enabled: caps.supportsArtistFilter,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: '画师筛选',
                    hintText: caps.supportsArtistFilter ? '输入画师名' : '当前图源不支持',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitSearch(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _uploaderController,
                  focusNode: _uploaderFocusNode,
                  enabled: caps.supportsUploaderFilter,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: '上传者筛选',
                    hintText: caps.supportsUploaderFilter ? '输入上传者用户名' : '当前图源不支持',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitSearch(),
                ),
              ),
            ],
          ),
          if (caps.supportsSort && caps.sortOptions.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: caps.sortOptions.map((opt) {
                  final selected = (_selectedSort ?? '') == opt.value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(opt.label, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        setState(() => _selectedSort = opt.value);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (caps.uploaderHint != null || caps.artistHint != null) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (!caps.supportsUploaderFilter && caps.uploaderHint != null)
                  caps.uploaderHint!,
                if (caps.artistHint != null) caps.artistHint!,
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _uploaderController.clear();
                  _artistController.clear();
                  setState(() => _selectedSort = null);
                },
                child: const Text('重置筛选'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _submitSearch,
                child: const Text('应用并搜索'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 230),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = _suggestions[index];
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _categoryLabel(item.category),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  if (item.postCount != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${item.postCount}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.outline,
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () => _acceptSuggestion(item),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchHub(ThemeData theme) {
    final recentTags = context.watch<RecentTagsNotifier>();
    final presets = recentTags.quickSearches;
    final tags = recentTags.tags;
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([
        FollowedTagsService.instance,
        BlacklistService.instance,
      ]),
      builder: (context, _) {
        final followedTags = FollowedTagsService.instance.tags;

        if (presets.isEmpty && tags.isEmpty && followedTags.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_rounded, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  '输入标签或打开筛选查找作品',
                  style: TextStyle(color: Colors.grey[500], fontSize: 15),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 86),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (presets.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          '快速搜索预设',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.bookmarks_outlined, size: 16),
                          label: const Text('清空预设'),
                          onPressed: () => recentTags.clearQuickSearches(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((entry) {
                        return InputChip(
                          avatar: Icon(
                            Icons.bookmark_rounded,
                            size: 16,
                            color: cs.primary,
                          ),
                          label: Text(
                            entry.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () => recentTags.removeQuickSearch(entry.id),
                          onPressed: () => _submitSearch(
                            overrideQuery: entry.query,
                            overrideUploader: entry.uploader,
                            overrideArtist: entry.artist,
                            overrideSort: entry.sort,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (followedTags.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          '特别关注',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.star_outline_rounded, size: 16),
                          label: const Text('清空关注'),
                          onPressed: () =>
                              FollowedTagsService.instance.clearAll(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: followedTags.map((tag) {
                        return GestureDetector(
                          onLongPress: () => showTagActionSheet(
                            context,
                            tag,
                            onSearchTag: () =>
                                _submitSearch(overrideQuery: tag),
                          ),
                          onSecondaryTap: () => showTagActionSheet(
                            context,
                            tag,
                            onSearchTag: () =>
                                _submitSearch(overrideQuery: tag),
                          ),
                          child: InputChip(
                            avatar: Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                            label: Text(
                              tag.replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 13),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () =>
                                FollowedTagsService.instance.removeTag(tag),
                            onPressed: () => _submitSearch(overrideQuery: tag),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (tags.isNotEmpty) ...[
                    Row(
                      children: [
                        Text(
                          '最近搜索',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.delete_sweep, size: 16),
                          label: const Text('清空'),
                          onPressed: () => recentTags.clear(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tags.map((tag) {
                        final isFollowed =
                            FollowedTagsService.instance.isFollowed(tag);
                        return GestureDetector(
                          onLongPress: () => showTagActionSheet(
                            context,
                            tag,
                            onSearchTag: () =>
                                _submitSearch(overrideQuery: tag),
                          ),
                          onSecondaryTap: () => showTagActionSheet(
                            context,
                            tag,
                            onSearchTag: () =>
                                _submitSearch(overrideQuery: tag),
                          ),
                          child: InputChip(
                            avatar: isFollowed
                                ? Icon(
                                    Icons.star_rounded,
                                    size: 15,
                                    color: cs.primary,
                                  )
                                : null,
                            label: Text(
                              tag,
                              style: const TextStyle(fontSize: 13),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => recentTags.removeTag(tag),
                            onPressed: () => _submitSearch(overrideQuery: tag),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
