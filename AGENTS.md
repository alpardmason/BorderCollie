# BorderCollie Project Guide

## Project Tech Stack And Environment

- App type: macOS SwiftUI app.
- Project format: Xcode project at `BorderCollie.xcodeproj`.
- Language: Swift.
- UI framework: SwiftUI with `NavigationSplitView` and native toolbars.
- Tests: Swift Testing in `BorderCollieTests`.
- Current deployment target: macOS 26.5.
- Current bundle identifier: `Alpard.BorderCollie`.
- App sandbox: disabled for the app target because trackers need access to
  local agent credentials, subprocess credential lookup, and network quota
  requests.

## Repository Layout

- `BorderCollie/BorderCollieApp.swift`: app entry point.
- `BorderCollie/ContentView.swift`: root sidebar/detail navigation.
- `BorderCollie/UsageTrackerView.swift`: shared tracker UI, toolbar refresh,
  auto-refresh loop, and preview-safe rendering.
- `BorderCollie/UsageTrackerViewModel.swift`: loading state, refresh lifecycle,
  timeout handling, and quota state.
- `BorderCollie/UsageTrackingService.swift`: shared tracker service and HTTP
  client protocols.
- `BorderCollie/CodexUsageView.swift`: Codex-specific tracker wrapper.
- `BorderCollie/CodexQuotaService.swift`: coordinates credentials and quota
  client.
- `BorderCollie/CodexCredentialResolver.swift`: Codex credential discovery and
  parsing.
- `BorderCollie/CodexUsageClient.swift`: Codex quota HTTP client and response
  normalization.
- `BorderCollie/CursorUsageView.swift`: Cursor-specific tracker wrapper.
- `BorderCollie/CursorQuotaService.swift`: coordinates Cursor credentials and
  quota client.
- `BorderCollie/CursorCredentialResolver.swift`: Cursor IDE auth-token
  discovery from Cursor's local `state.vscdb`.
- `BorderCollie/CursorUsageClient.swift`: Cursor current-period usage client
  and response normalization.
- `BorderCollie/CodexUsageModels.swift`: normalized quota models and shared
  formatting helpers.
- `BorderCollie/CodexUsageDisplay.swift`: display-policy helpers for usage
  rows.
- `BorderCollie/CursorUsageDisplay.swift`: Cursor monthly usage row labels.
- `docs/tracker_design.md`: design guide for adding future usage trackers.

## Common Commands

Use this for non-launching compile verification:

```sh
xcodebuild build-for-testing -project BorderCollie.xcodeproj -scheme BorderCollie -destination 'platform=macOS' -derivedDataPath /private/tmp/BorderCollieDerivedDataBuild CODE_SIGNING_ALLOWED=NO
```

Avoid direct app-hosted `xcodebuild test` unless you specifically need it and
are prepared for the app UI to launch.

## Current Usage Tracker Standard

- Query automatically when a tracker page opens.
- Refresh automatically every 30 seconds.
- Keep manual Refresh in the top toolbar.
- Show `Usage remaining`, not usage consumed.
- Use native SwiftUI `ProgressView` bars.
- Keep updated time static until the next refresh.
- Do not show auth implementation details in the happy path.
- Disable live refresh/network behavior in previews.

## Common Errors And Pitfalls

### Symptom: app UI pops up or test command hangs

- Root cause: app-hosted macOS tests can launch the app process.
- Fix: use `xcodebuild build-for-testing` for compile verification.
- Prevention: keep model/client logic unit-testable and avoid requiring full app
  launches for basic checks.

### Symptom: Codex query spins forever

- Root cause: missing timeout, blocking credential lookup, or overlapping
  refreshes.
- Fix: preserve the Keychain timeout, HTTP timeout, full refresh timeout, and
  `isLoading` guard.
- Prevention: future trackers must use explicit timeouts for file, subprocess,
  and network work.

### Symptom: preview tries to query real credentials or network

- Root cause: preview instantiated the live view model and auto-refresh loop.
- Fix: inject sample quota data and pass `runsAutoRefresh: false`.
- Prevention: every tracker preview should use local sample data only.

### Symptom: `#Preview` macro fails in sandboxed command-line build

- Root cause: Swift preview macro plugin server can fail under the sandbox.
- Fix: use `PreviewProvider`.
- Prevention: prefer `PreviewProvider` in this project until the macro-server
  environment is known to be stable.

### Symptom: usage percentage appears inverted

- Root cause: provider API reports used percentage while the UI displays
  remaining percentage.
- Fix: store provider value as `QuotaTier.utilization`, then display
  `100 - utilization`.
- Prevention: document each provider's percentage semantics before normalizing.

### Symptom: "Updated" time changes every second

- Root cause: using relative date display.
- Fix: show a static time based on `queriedAt`.
- Prevention: updated timestamps should change only when refresh produces a new
  query result.

### Symptom: credential lookup fails after re-enabling sandbox

- Root cause: sandbox restrictions block user auth files, local Cursor state,
  Keychain/sqlite subprocesses, or network access.
- Fix: keep sandbox disabled or add an explicit entitlement strategy.
- Prevention: retest Keychain, `~/.codex/auth.json`, Cursor `state.vscdb`, and
  remote usage calls when changing signing or sandbox settings.

### Symptom: Cursor tracker shows missing credentials while Cursor is signed in

- Root cause: Cursor moved or renamed its local auth database, or the
  `cursorAuth/accessToken` key is absent.
- Fix: inspect `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  and update `CursorCredentialResolver` if Cursor changed storage layout.
- Prevention: keep Cursor credential lookup isolated and covered by resolver
  tests.

## Key Technical Decision Records

### Decision: normalize tracker output into `SubscriptionQuota`

- Context: different agents may expose usage through different APIs, files, or
  CLI commands.
- Alternatives considered: render each provider response directly in SwiftUI.
- Rationale: one normalized model keeps UI consistent and makes future tracker
  additions testable.

### Decision: keep used percentage in the model and convert in display

- Context: Codex reports `used_percent`, but the UI should show usage remaining.
- Alternatives considered: overwrite the model with remaining percentage.
- Rationale: preserving provider semantics avoids confusion in client tests and
  keeps display policy separate.

### Decision: fixed 30-second auto refresh

- Context: the user should not need to click Refresh during normal operation.
- Alternatives considered: user-selectable 5s, 30s, or 1m cadence.
- Rationale: a fixed cadence keeps the UI simpler and avoids unnecessary
  provider polling choices.

### Decision: manual refresh belongs in the toolbar

- Context: manual refresh is a fallback action, not content.
- Alternatives considered: place Refresh inside the detail page header.
- Rationale: toolbar placement is more native for a macOS command and keeps the
  page focused on usage data.

### Decision: disable live auto refresh in previews

- Context: previews should be fast, deterministic, and safe.
- Alternatives considered: let previews use the live view model.
- Rationale: live previews would read local credentials and call remote APIs.

### Decision: use `build-for-testing` as the default verification command

- Context: direct app-hosted tests launched the UI and could hang after
  assertions passed.
- Alternatives considered: run full `xcodebuild test` after every change.
- Rationale: `build-for-testing` catches compile errors without disrupting the
  desktop session.

### Decision: extract a shared tracker view and view model

- Context: Cursor is the second tracker and shares Codex's refresh, timeout,
  toolbar, preview, and usage-card behavior.
- Alternatives considered: duplicate the Codex view/model and rename files.
- Rationale: shared `UsageTrackerView` and `UsageTrackerViewModel` keep tracker
  behavior consistent while provider-specific credential and API details remain
  isolated.

### Decision: Cursor uses IDE auth plus current-period dashboard usage

- Context: Cursor CLI/agent exposes auth and model commands but not the monthly
  split shown in the usage dashboard. Cursor IDE stores an access token in local
  state, and `DashboardService/GetCurrentPeriodUsage` returns the monthly
  `Auto + Composer` and `API` usage percentages plus billing-cycle reset.
- Alternatives considered: scrape UI/dashboard HTML, call Cursor CLI, or require
  a team Admin API key.
- Rationale: the IDE-token dashboard call matches the personal Pro+ dashboard
  with no extra setup; the Admin API is better for teams but not the least
  friction path for this app.

## Future Tracker Guidance

Read `docs/tracker_design.md` before adding another tracker such as Claude
Code.

When adding future trackers, preserve:

- normalized quota model,
- 30-second auto refresh,
- toolbar refresh fallback,
- native usage bars,
- static updated timestamp,
- credential isolation outside SwiftUI,
- injected clients for tests,
- preview-only sample data.

## Maintenance Notes

- Do not commit credentials, auth files, tokens, or local DerivedData.
- Do not revert user UI tweaks without asking.
- Keep comments sparse and focused on non-obvious behavior.
- Update this file after significant architecture or workflow changes.
