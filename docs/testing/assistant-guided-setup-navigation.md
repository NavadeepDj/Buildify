# Assistant Guided Setup Navigation Runbook (Issue #145)

## Overview
This runbook unblocks the manual QA access gate for **Issue #145** / **PR #146** by providing direct, supported navigation paths to `AiServerShell`, the Model Setup Assistant, and deliberate public-sharing controls from the primary application routes on Windows and Android.

---

## Primary Navigation Path (From App Home)

1. **Launch Buildify** (Normal application launch on Windows Desktop or Android).
2. On the **Projects Home Page** (`ProjectsHomePage`), tap the **`+ Add New`** button in the header.
3. The **"select service type"** modal dialog opens.
4. Tap the **`model setup assistant`** option (highlighted with the sparkle `✨` icon: *"Guided AI server setup, hardware tuning & public sharing"*).
5. **Expected Result:**
   - The app navigates to **`AiServerShell`** (`Buildify AI`).
   - The screen displays 4 primary tabs: **Home**, **Models**, **Self test**, **Network**.
   - No model download is triggered automatically upon entry.

---

## Secondary Navigation Path (From Model Selection Screen)

1. On the **Projects Home Page**, tap **`+ Add New`**.
2. Tap **`run an ai model`** (manual model catalog).
3. At the top of `AiModelSelectPage` (below the header), locate the **`model setup assistant`** banner:
   - *"Want guidance? Launch the assistant to review your setup plan and sharing options before downloading any weights."*
4. Tap the **`OPEN`** button on the banner.
5. **Expected Result:**
   - The app navigates directly to `AiServerShell`.

---

## Reaching Deliberate Public-Sharing Controls

1. From `AiServerShell`, tap the **`Network`** tab in the bottom navigation bar.
2. Verify:
   - **Local IP & Port** are displayed.
   - **Auth mode** is indicated (API key required vs Open).
   - **Copy API URL** action button works.
   - **Cloudflare Tunnel** controls are present for deliberate public sharing.
   - Tap the Back button in the top AppBar to cleanly return to `ProjectsHomePage`.

---

## Automated Verification

Run the automated regression test suite:
```powershell
flutter test test/navigation/assistant_guided_setup_navigation_test.dart
```

