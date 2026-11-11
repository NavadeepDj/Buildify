# Issue: Show Guided Tour Only to First-Time Users (State 0 vs 1)

**Status**: Resolved  
**Component**: Guided Tour & Onboarding (`lib/services/guided_tour_service.dart`, `lib/pages/`)  
**Assignee**: Haritha Reddy  
**Date**: 2026-11-11  

---

## 1. Problem Statement
Returning / existing users were repeatedly seeing the step-by-step guided tour walkthrough every time they opened certain pages (`AiModelSelectPage`, `HostProjectWizard`, and Home).
- Hardcoded `startTour()` calls on certain pages bypassed completion checks.
- Storage read failures defaulted to restarting the tour.
- Returning users with existing projects were not recognized as old users.

## 2. Root Cause
- `AiModelSelectPage` and `HostProjectWizard` called `startTour()` directly in `initState` instead of checking prior completion.
- `GuidedTourNotifier.checkAndAutoStartTour` had a fallback catch block that defaulted to launching the tour on any read hiccup.
- No check existed on the home dashboard to verify if the user already had established projects in the database.

## 3. Solution Implemented
Implemented a binary state check (**0 = First-Time User**, **1 = Returning / Old User**):
1. **Persistent State Logic** (`lib/services/guided_tour_service.dart`):
   - Reads tour state: If `'1'` or `'true'`, user is an old user -> tour is completely suppressed.
   - If `'0'` or `null`, user is brand new -> launches the tour once.
   - When the user finishes or clicks **"Skip"**, state `'1'` is saved in persistent storage.
   - Storage read errors now quietly default to suppressing the tour rather than interrupting the user.
2. **Eliminated Hardcoded Triggers**:
   - `lib/pages/ai_model_select_page.dart`: Changed to `checkAndAutoStartTour` with key `'buildify_tour_ai_models'`.
   - `lib/pages/host_project_wizard.dart`: Changed source and config steps to `checkAndAutoStartTour` with keys `'buildify_tour_wizard_source'` and `'buildify_tour_wizard_config'`.
3. **Smart Old User Detection** (`lib/pages/projects_home_page.dart`):
   - If `backendProjectsProvider` contains existing projects, the user is automatically recognized as an existing user, state `'1'` is persisted, and the onboarding walkthrough is bypassed.

