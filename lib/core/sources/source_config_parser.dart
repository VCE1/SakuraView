import 'dart:convert';
import 'package:vce1_sakuraview/core/sources/source_models.dart';

/// Venera 风格图源清单（单个 JSON 对象或 `index.json` 列表）校验与解析器。
class SourceConfigParser {
  SourceConfigParser._();

  static final RegExp _validIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{1,47}$');

  /// 从 JSON 字符串解析一个或多个图源配置。
  ///
  /// 所有外部导入图源默认处于禁用状态（`isEnabled: false`），
  /// 必须由用户在「图源管理」中手动启用后才会进入首页或搜索列表。
  static List<SourceDescriptor> parseImportPayload(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('图源配置 JSON 不能为空');
    }

    final dynamic decoded = json.decode(trimmed);
    final List<Map<String, dynamic>> rawItems = [];

    if (decoded is Map<String, dynamic>) {
      if (decoded['sources'] is List) {
        for (final item in decoded['sources'] as List) {
          if (item is Map<String, dynamic>) {
            rawItems.add(item);
          }
        }
      } else {
        rawItems.add(decoded);
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          rawItems.add(item);
        }
      }
    } else {
      throw const FormatException('不支持的 JSON 结构：根节点须为对象或数组');
    }

    if (rawItems.isEmpty) {
      throw const FormatException('未在 JSON 中找到有效的图源配置项');
    }

    final parsed = <SourceDescriptor>[];
    final seenIds = <String>{};

    for (final item in rawItems) {
      final descriptor = validateAndBuild(item, forceDisabled: true);
      if (seenIds.contains(descriptor.id)) {
        throw FormatException('导入清单中存在重复的图源 ID: ${descriptor.id}');
      }
      seenIds.add(descriptor.id);
      parsed.add(descriptor);
    }

    return parsed;
  }

  /// 校验单个原始 Map 并构建 [SourceDescriptor]。
  static SourceDescriptor validateAndBuild(
    Map<String, dynamic> json, {
    bool isBuiltIn = false,
    bool forceDisabled = true,
  }) {
    final rawId = (json['id'] ?? json['key'] ?? '').toString().trim().toLowerCase();
    if (rawId.isEmpty) {
      throw const FormatException('缺少必填字段 "id"');
    }
    if (!_validIdPattern.hasMatch(rawId)) {
      throw FormatException(
        '图源 ID "$rawId" 格式无效：仅允许小写字母、数字、下划线或短横线，长度 2~48',
      );
    }

    final name = (json['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      throw FormatException('图源 "$rawId" 缺少必填字段 "name"');
    }

    final baseUrl = (json['baseUrl'] ?? json['url'] ?? '').toString().trim();
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw FormatException('图源 "$rawId" 的 baseUrl 必须为合法的 http/https 地址');
    }

    return SourceDescriptor.fromJson(
      json,
      isBuiltIn: isBuiltIn,
      forceDisabledOnImport: forceDisabled,
    );
  }

  static String encodePretty(List<SourceDescriptor> descriptors) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(
      descriptors.map((e) => e.toJson(includeEnabledState: false)).toList(),
    );
  }

  static String encodeSingle(SourceDescriptor descriptor) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(descriptor.toJson(includeEnabledState: false));
  }
}
