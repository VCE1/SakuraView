import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('关于 SakuraView'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // App Header Card
          Card(
            elevation: 0,
            color: cs.primaryContainer.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.filter_vintage_rounded,
                        size: 42,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'SakuraView',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '版本 1.2.0 (Build 2026.11)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.favorite_rounded, size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          '感谢使用 SakuraView！',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Thank You & Vision
          _buildSectionHeader(context, '致谢与寄语', Icons.chat_bubble_outline_rounded),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '十分感谢您使用 SakuraView。\n'
                '本应用专为动漫二次元插画爱好者倾力打造，致力于提供跨站点、统一且流畅优雅的高清插画浏览、检索、账户会话同步与本地离线归档体验。'
                '无论您是在手机还是在平板横屏设备上，都能享受沉浸无拘的视觉盛宴。',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
              ),
            ),
          ),

          // Supported Sites
          _buildSectionHeader(context, '当前支持的站点', Icons.public_rounded),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildSiteTile(
                    title: 'Danbooru',
                    badge: 'API & 网页登录',
                    desc: '全球知名的动漫标签索引数据库，支持 API 密钥授权、WebView 会话同步及云端收藏检索 (ordfav:<user>)。',
                    color: Colors.blueAccent,
                  ),
                  const Divider(height: 16),
                  _buildSiteTile(
                    title: 'Yande.re (Moebooru)',
                    badge: '无限制高清大图',
                    desc: '收录海量高清动漫壁纸与插画，支持评分收藏 (vote:3:<user>) 与内置 Cookie 会话保持。',
                    color: Colors.deepOrangeAccent,
                  ),
                  const Divider(height: 16),
                  _buildSiteTile(
                    title: 'Zerochan',
                    badge: '角色与画风索引',
                    desc: '角色作品标签细分导向的知名画廊，支持原图自动嗅探解析、网页登录与个人收藏同步 (fav=<user>)。',
                    color: Colors.teal,
                  ),
                  const Divider(height: 16),
                  _buildSiteTile(
                    title: 'Konachan',
                    badge: '壁纸社区',
                    desc: 'Moebooru 架构的高分辨率插画站，同源兼容 Yande.re 核心引擎。',
                    color: Colors.purpleAccent,
                  ),
                ],
              ),
            ),
          ),

          // Architecture & Tech Highlights
          _buildSectionHeader(context, '项目结构与核心设计', Icons.layers_outlined),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFeatureBullet(
                    context,
                    title: '自适应平板横屏与手机端',
                    desc: '横屏模式下精简顶部占用，采用大视野瀑布流网格，适配各类屏幕比例。',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(
                    context,
                    title: 'Telegram 风格平滑动画浮动栏',
                    desc: '支持滚动上下平滑收缩出现/消失动画，未选中态精简图标，选中态平滑展开药丸胶囊，告别文字截断。',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(
                    context,
                    title: '独立站点账户与原生 WebView Cookie 保持',
                    desc: '各站点独立配置 API 与登录凭据，内置原生 Android WebView 登录拦截，自动持久化会话 Cookie。',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(
                    context,
                    title: '双重收藏机制 (云端账户 + 本地离线)',
                    desc: '登录站点后直接查看在线云端收藏夹，并支持一键将云端作品同步转存至本地离线数据库。',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(
                    context,
                    title: '规范化网络路由策略 (跟随系统 / 自定义 / 直连)',
                    desc: '全面遵循操作系统网络标准，支持系统代理探测、用户指定 HTTP 代理、绕过名单与全局 TUN 隧道。',
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureBullet(
                    context,
                    title: '开放存储路径管理',
                    desc: '支持用户自由选择公开系统相册 (Pictures/SakuraView)、下载目录 (Download)、相机相册 (DCIM) 或应用私有隔离存储。',
                  ),
                ],
              ),
            ),
          ),

          // Open Source Credits
          _buildSectionHeader(context, '致敬与开源参考', Icons.code_rounded),
          Card(
            margin: const EdgeInsets.only(top: 8, bottom: 24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SakuraView 在研发与重构过程中，参考并汲取了以下优秀开源项目的成熟设计方案与灵感：',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCreditItem(context, 'pixes-app/pixes', '优雅的加载过渡动画方案与下载管理架构参考'),
                  _buildCreditItem(context, 'Boorusama', '成熟的 Booru 多站点架构与标签检索规范参考'),
                  _buildCreditItem(context, 'Telegram Android', '极简半透明圆角悬浮底部导航栏交互灵感'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
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
    );
  }

  Widget _buildSiteTile({
    required String title,
    required String badge,
    required String desc,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureBullet(
    BuildContext context, {
    required String title,
    required String desc,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCreditItem(BuildContext context, String name, String desc) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                children: [
                  TextSpan(
                    text: '$name: ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
                  ),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
