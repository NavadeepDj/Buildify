import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:buildify_flutter/services/guided_tour_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dummySteps = [
    GuidedTourStep(
      title: 'Step 1',
      description: 'Test Description 1',
      targetKey: GlobalKey(),
    ),
    GuidedTourStep(
      title: 'Step 2',
      description: 'Test Description 2',
      targetKey: GlobalKey(),
    ),
  ];

  group('GuidedTourService - State 0 vs State 1', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('1st User (State 0 / null): Guided tour automatically launches', () async {
      final notifier = GuidedTourNotifier();

      expect(notifier.state.isActive, isFalse);

      // Auto start on first launch
      await notifier.checkAndAutoStartTour(dummySteps);

      // Tour should be ACTIVE for first-time user
      expect(notifier.state.isActive, isTrue);
      expect(notifier.state.currentStepIndex, 0);
      expect(notifier.state.currentStep?.title, 'Step 1');
    });

    test('Completing or skipping tour transitions state to 1 (Old User)', () async {
      final notifier = GuidedTourNotifier();
      const storage = FlutterSecureStorage();

      await notifier.checkAndAutoStartTour(dummySteps);
      expect(notifier.state.isActive, isTrue);

      // User taps "Got It" / "Skip"
      await notifier.completeTour();

      expect(notifier.state.isActive, isFalse);

      // Master variable should now be '1' (Old User)
      final masterStatus = await storage.read(key: 'buildify_user_tour_status');
      expect(masterStatus, '1');
    });

    test('Old User (State 1): Guided tour is NEVER shown on subsequent launches', () async {
      final notifier = GuidedTourNotifier();

      // Complete tour once
      await notifier.checkAndAutoStartTour(dummySteps);
      await notifier.completeTour();

      // User re-opens app or visits other screens
      await notifier.checkAndAutoStartTour(dummySteps);
      expect(notifier.state.isActive, isFalse, reason: 'Old user should not see tour');

      // Even on other sub-screens with different tourKeys, master state 1 prevents the tour
      await notifier.checkAndAutoStartTour(dummySteps, tourKey: 'buildify_tour_wizard_source');
      expect(notifier.state.isActive, isFalse, reason: 'Master state 1 blocks wizard tour');

      await notifier.checkAndAutoStartTour(dummySteps, tourKey: 'buildify_tour_ai_models');
      expect(notifier.state.isActive, isFalse, reason: 'Master state 1 blocks AI models tour');
    });
  });
}

