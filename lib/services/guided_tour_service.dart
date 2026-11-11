import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storageKeyHasCompletedTour = 'buildify_has_completed_guided_tour';

/// Model representing a step in the guided onboarding tour.
class GuidedTourStep {
  const GuidedTourStep({
    required this.title,
    required this.description,
    required this.targetKey,
    this.tooltipPosition = TooltipPosition.bottom,
  });

  final String title;
  final String description;
  final GlobalKey targetKey;
  final TooltipPosition tooltipPosition;
}

enum TooltipPosition { top, bottom }

/// State model for the guided tour.
class GuidedTourState {
  const GuidedTourState({
    this.isActive = false,
    this.currentStepIndex = 0,
    this.steps = const [],
  });

  final bool isActive;
  final int currentStepIndex;
  final List<GuidedTourStep> steps;

  GuidedTourStep? get currentStep {
    if (currentStepIndex >= 0 && currentStepIndex < steps.length) {
      return steps[currentStepIndex];
    }
    return null;
  }

  bool get isLastStep => currentStepIndex == steps.length - 1;
  bool get isFirstStep => currentStepIndex == 0;

  GuidedTourState copyWith({
    bool? isActive,
    int? currentStepIndex,
    List<GuidedTourStep>? steps,
  }) {
    return GuidedTourState(
      isActive: isActive ?? this.isActive,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      steps: steps ?? this.steps,
    );
  }
}

class GuidedTourNotifier extends StateNotifier<GuidedTourState> {
  GuidedTourNotifier() : super(const GuidedTourState());

  static const _storage = FlutterSecureStorage();

  // Which completion key the currently-active tour writes to when finished.
  String _activeTourKey = _storageKeyHasCompletedTour;

  /// Checks storage and starts the tour if it's the user's first launch (state 0).
  /// Once seen, the state becomes 1 (old user) and the tour never auto-starts again.
  Future<void> checkAndAutoStartTour(
    List<GuidedTourStep> steps, {
    String tourKey = _storageKeyHasCompletedTour,
  }) async {
    try {
      final status = await _storage.read(key: tourKey);
      // '1' or 'true' means old user: do NOT start tour
      if (status == '1' || status == 'true') {
        return;
      }
      // '0' or null means brand new first-time user: start tour
      startTour(steps, tourKey: tourKey);
    } catch (_) {
      // On storage read error, do NOT force tour on returning users
    }
  }

  /// Manually starts the guided tour with a given list of steps.
  void startTour(
    List<GuidedTourStep> steps, {
    String tourKey = _storageKeyHasCompletedTour,
  }) {
    if (steps.isEmpty) return;
    _activeTourKey = tourKey;
    state = GuidedTourState(
      isActive: true,
      currentStepIndex: 0,
      steps: steps,
    );
  }

  /// Move to the next step or finish if on the last step.
  void nextStep() {
    if (!state.isActive) return;
    if (state.isLastStep) {
      completeTour();
    } else {
      state = state.copyWith(currentStepIndex: state.currentStepIndex + 1);
    }
  }

  /// Move to the previous step.
  void previousStep() {
    if (!state.isActive || state.isFirstStep) return;
    state = state.copyWith(currentStepIndex: state.currentStepIndex - 1);
  }

  /// Skip or complete the tour and persist state as 1 (old user).
  Future<void> completeTour() async {
    state = state.copyWith(isActive: false);
    try {
      // Save state as '1' (completed / old user)
      await _storage.write(key: _activeTourKey, value: '1');
    } catch (_) {}
  }

  /// Reset tour completion state (for testing or settings option).
  Future<void> resetTourState() async {
    try {
      await _storage.delete(key: _storageKeyHasCompletedTour);
    } catch (_) {}
  }
}

final guidedTourNotifierProvider =
    StateNotifierProvider<GuidedTourNotifier, GuidedTourState>((ref) {
  return GuidedTourNotifier();
});
