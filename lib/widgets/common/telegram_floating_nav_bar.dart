import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FloatingNavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badgeCount;

  const FloatingNavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// Mature floating glassmorphic pill navigation bar inspired by Telegram Android,
/// Boorusama, and Material 3 Expressive Floating Dock:
/// - Smooth appear / disappear animation (`SlideTransition` + `FadeTransition` + `ScaleTransition`)
///   driven by an explicit [AnimationController].
/// - Expandable active capsule: unselected tabs show crisp icons only (eliminating
///   any text truncation), while the selected tab smoothly expands to show its
///   icon + concise label with an elastic curve.
class TelegramFloatingNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool visible;
  final int activeDownloadCount;

  const TelegramFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.visible = true,
    this.activeDownloadCount = 0,
  });

  @override
  State<TelegramFloatingNavBar> createState() => _TelegramFloatingNavBarState();
}

class _TelegramFloatingNavBarState extends State<TelegramFloatingNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _visibilityCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _visibilityCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
      value: widget.visible ? 1.0 : 0.0,
    );
    _fadeAnim = CurvedAnimation(
      parent: _visibilityCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1.45),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _visibilityCtrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _visibilityCtrl,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void didUpdateWidget(TelegramFloatingNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _visibilityCtrl.forward();
      } else {
        _visibilityCtrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _visibilityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final bottomInset = media.padding.bottom;

    final items = <FloatingNavItemData>[
      const FloatingNavItemData(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore_rounded,
        label: '画廊',
      ),
      const FloatingNavItemData(
        icon: Icons.search_rounded,
        activeIcon: Icons.manage_search_rounded,
        label: '搜索',
      ),
      const FloatingNavItemData(
        icon: Icons.favorite_border_rounded,
        activeIcon: Icons.favorite_rounded,
        label: '收藏',
      ),
      FloatingNavItemData(
        icon: Icons.download_outlined,
        activeIcon: Icons.downloading_rounded,
        label: '下载',
        badgeCount: widget.activeDownloadCount,
      ),
    ];

    final double barHeight = isLandscape ? 50.0 : 56.0;
    final double bottomMargin =
        (bottomInset > 0 ? bottomInset : (isLandscape ? 8.0 : 14.0));

    final Color glassBg = isDark
        ? cs.surfaceContainerHigh.withAlpha(205)
        : cs.surface.withAlpha(220);

    final Color borderColor = isDark
        ? Colors.white.withAlpha(32)
        : cs.outlineVariant.withAlpha(110);

    final Color pillActiveBg = isDark
        ? cs.primary.withAlpha(58)
        : cs.primaryContainer.withAlpha(210);

    final Color activeFg = isDark ? cs.primary : cs.onPrimaryContainer;
    final Color inactiveFg = isDark
        ? cs.onSurface.withAlpha(170)
        : cs.onSurfaceVariant.withAlpha(185);

    return AnimatedBuilder(
      animation: _visibilityCtrl,
      builder: (context, child) {
        if (_visibilityCtrl.value == 0.0) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: !widget.visible && _visibilityCtrl.value < 0.3,
          child: SlideTransition(
            position: _slideAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: child,
              ),
            ),
          ),
        );
      },
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: bottomMargin,
            top: 4,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1.0,
            child: Container(
              height: barHeight,
              constraints: BoxConstraints(
                maxWidth: isLandscape ? 370 : 340,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 95 : 34),
                    blurRadius: 24,
                    spreadRadius: 1,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: glassBg,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: borderColor,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(items.length, (i) {
                        final item = items[i];
                        final selected = i == widget.currentIndex;
                        return _ExpandablePillNavItem(
                          item: item,
                          selected: selected,
                          activeFg: activeFg,
                          inactiveFg: inactiveFg,
                          pillActiveBg: pillActiveBg,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onDestinationSelected(i);
                          },
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandablePillNavItem extends StatelessWidget {
  final FloatingNavItemData item;
  final bool selected;
  final Color activeFg;
  final Color inactiveFg;
  final Color pillActiveBg;
  final VoidCallback onTap;

  const _ExpandablePillNavItem({
    required this.item,
    required this.selected,
    required this.activeFg,
    required this.inactiveFg,
    required this.pillActiveBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 16 : 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected ? pillActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: Tween<double>(begin: 0.78, end: 1.0).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    selected ? item.activeIcon : item.icon,
                    key: ValueKey<bool>(selected),
                    size: 21,
                    color: selected ? activeFg : inactiveFg,
                  ),
                ),
                if (item.badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        item.badgeCount > 9 ? '9+' : '${item.badgeCount}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Text(
                        item.label,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: activeFg,
                          letterSpacing: 0.2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
