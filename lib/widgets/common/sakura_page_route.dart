import 'dart:io';
import 'package:flutter/material.dart';

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

  SakuraPageRoute({
    required this.builder,
    super.settings,
    this.preventRebuild = true,
    this.isRoot = false,
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
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

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
    if (Platform.isAndroid) {
      return const PredictiveBackPageTransitionsBuilder().buildTransitions(
        this,
        context,
        animation,
        secondaryAnimation,
        child,
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
