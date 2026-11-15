import 'dart:io';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:vce1_sakuraview/widgets/common/sakura_drawer_swipe_region.dart';

/// Entrance transition inspired by pixes's `EntrancePageTransition` & `DrillInPageTransition`.
class SakuraEntranceTransition extends StatelessWidget {
  final Widget child;
  final Animation<double> animation;
  final Offset beginOffset;

  const SakuraEntranceTransition({
    super.key,
    required this.child,
    required this.animation,
    this.beginOffset = const Offset(0, 0.045),
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: beginOffset,
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(
        opacity: curved,
        child: child,
      ),
    );
  }
}

/// Custom route modeled after pixes's `AppPageRoute`:
/// - Uses `PredictiveBackPageTransitionsBuilder` on Android for native gesture back feel
/// - Uses smooth Drill-In (`ScaleTransition` + `FadeTransition`) on Windows/Desktop
/// - Caches built content (`preventRebuild: true`) so transition animations don't re-trigger widget builds
class SakuraPageRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final bool preventRebuild;
  final bool isRoot;
  final bool enableSwipeBack;

  SakuraPageRoute({
    required this.builder,
    super.settings,
    this.preventRebuild = true,
    this.isRoot = false,
    this.enableSwipeBack = true,
    super.fullscreenDialog,
  });

  Widget? _cachedChild;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final Widget result = preventRebuild
        ? (_cachedChild ??= builder(context))
        : builder(context);
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: result,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (isRoot) {
      return SakuraEntranceTransition(
        animation: animation,
        child: child,
      );
    }
    if (enableSwipeBack) {
      child = SakuraDrawerSwipeDetector(
        minLeftStartWidth: Platform.isIOS ? 24.0 : 0.0,
        maxLeftStartWidth: 88.0,
        leftZoneFraction: 0.28,
        onSwipeRightFromLeft: () {
          final nav = navigator;
          if (isCurrent &&
              canPop &&
              nav != null &&
              !nav.userGestureInProgress) {
            nav.maybePop();
          }
        },
        child: child,
      );
    }
    if (Platform.isIOS) {
      return const CupertinoPageTransitionsBuilder().buildTransitions(
        this,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    if (Platform.isAndroid) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.05, 0.0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: child,
        ),
      );
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}
