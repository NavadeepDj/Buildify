import 'package:flutter/material.dart';

final voiceOverlaysVisible = ValueNotifier<bool>(true);

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
