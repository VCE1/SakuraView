import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class TelegramNavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const TelegramNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Telegram Android-inspired floating translucent pill navigation bar.
/// Designed to be ultra-compact in Android landscape / tablet mode while
/// preserving rich frosted-glass depth and springy pill selection feedback.
class TelegramFloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<TelegramNavDestination> destinations;
  final bool visible;

  const TelegramFloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.visible = true,
    this.destinations = const [
      TelegramNavDestination(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: 'Home',
      ),
      TelegramNavDestination(
        icon: Icons.search_rounded,
        selectedIcon: Icons.search_rounded,
        label: 'Search',
      ),
      TelegramNavDestination(
        icon: Icons.favorite_outline_rounded,
        selectedIcon: Icons.favorite_rounded,
        label: 'Favorites',
      ),
      TelegramNavDestination(
        icon: Icons.download_outlined,
        selectedIcon: Icons.download_rounded,
        label: 'Downloads',
      ),
    ],
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape ||
        media.size.width >= 640;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final double barHeight = isLandscape ? 50.0 : 58.0;
    final double maxBarWidth = isLandscape ? 430.0 : 368.0;
    final double bottomMargin =
        (media.padding.bottom > 0 ? media.padding.bottom : 6.0) +
            (isLandscape ? 6.0 : 10.0);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 1.4),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: visible ? 1.0 : 0.0,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: bottomMargin,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: 1.0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxBarWidth,
                    minHeight: barHeight,
                    maxHeight: barHeight,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(isDark ? 95 : 36),
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
                          height: barHeight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(32),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isDark
                                  ? [
                                      const Color(0xFF25283D).withAlpha(185),
                                      const Color(0xFF181A29).withAlpha(205),
                                    ]
                                  : [
                                      Colors.white.withAlpha(215),
                                      Colors.white.withAlpha(185),
                                    ],
                            ),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withAlpha(36)
                                  : Colors.black.withAlpha(16),
                              width: 0.9,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(destinations.length, (i) {
                              final item = destinations[i];
                              final selected = i == currentIndex;
                              return Expanded(
                                flex: selected && isLandscape ? 13 : 10,
                                child: _TelegramNavItem(
                                  destination: item,
                                  selected: selected,
                                  isLandscape: isLandscape,
                                  colorScheme: cs,
                                  isDark: isDark,
                                  onTap: () => onDestinationSelected(i),
                                ),
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
          ),
        ),
      ),
    );
  }
}

class _TelegramNavItem extends StatelessWidget {
  final TelegramNavDestination destination;
  final bool selected;
  final bool isLandscape;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onTap;

  const _TelegramNavItem({
    required this.destination,
    required this.selected,
    required this.isLandscape,
    required this.colorScheme,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeBg = isDark
        ? colorScheme.primary.withAlpha(62)
        : colorScheme.primaryContainer.withAlpha(190);
    final Color activeFg = isDark
        ? const Color(0xFFFF85A2)
        : colorScheme.primary;
    final Color inactiveFg = isDark
        ? Colors.white.withAlpha(165)
        : Colors.black.withAlpha(150);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 10 : 6,
          vertical: isLandscape ? 6 : 4,
        ),
        decoration: BoxDecoration(
          color: selected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
        ),
        child: isLandscape
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.08 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 19,
                      color: selected ? activeFg : inactiveFg,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? activeFg : inactiveFg,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.12 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 20,
                      color: selected ? activeFg : inactiveFg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? activeFg : inactiveFg,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
