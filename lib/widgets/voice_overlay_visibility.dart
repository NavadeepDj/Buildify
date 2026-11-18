import 'package:flutter/material.dart';

final voiceOverlaysVisible = ValueNotifier<bool>(true);

/// Bottom clearance for scrollable pages under the global voice shortcuts.
class VoiceOverlayInset extends InheritedWidget {
  const VoiceOverlayInset({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VoiceOverlayInset>()?.bottom ??
      0;

  @override
  bool updateShouldNotify(VoiceOverlayInset oldWidget) =>
      bottom != oldWidget.bottom;
}

/// The global voice shortcuts must not cover a review page or a modal footer.
class VoiceOverlayRouteObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];
  int _revision = 0;

  void _update() {
    final top = _routes.lastOrNull;
    final visible =
        top is! PopupRoute &&
        !{
          '/voice-actions',
          '/voice-setup',
          '/voice-call',
        }.contains(top?.settings.name);
    final revision = ++_revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (revision == _revision) voiceOverlaysVisible.value = visible;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _update();
  }
}
