# BorderCollie

BorderCollie is a native macOS SwiftUI app for monitoring coding-agent usage
limits from one place. It currently tracks Codex and Cursor, showing remaining
usage, reset timing, and a static last-updated time in a compact desktop UI.

The app is intentionally local-first: credentials are read from provider-owned
local auth state, used only by provider-specific service/client layers, and are
not passed into SwiftUI views.

## Current Features

- Native macOS sidebar with Codex and Cursor usage trackers.
- Automatic query when a tracker page opens.
- Fixed 30-second auto refresh.
- Manual toolbar refresh.
- Usage remaining bars, not usage consumed.
- Static updated timestamp that changes only after a new query result.
- Preview-safe tracker screens with no live credential or network access.
- Unit coverage for credential parsing, response normalization, display
  formatting, and API error mapping.

## Supported Trackers

### Codex

Codex usage is fetched from:

```text
https://chatgpt.com/backend-api/wham/usage
```

Credential lookup order:

1. macOS Keychain generic password named `Codex Auth`.
2. `~/.codex/auth.json`.

The Codex tracker displays normalized 5-hour and weekly quota windows when the
provider returns them.

### Cursor

Cursor usage is fetched from:

```text
https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage
```

Credential lookup:

1. `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.
2. `ItemTable` key `cursorAuth/accessToken`.

The Cursor tracker displays current monthly `Auto + Composer` and `API`
remaining usage.

## Privacy And Security

BorderCollie reads local provider auth state so it can query the same usage
data visible in the provider apps or dashboards. The app does not hardcode
tokens, store copied tokens, or render tokens in the UI.

Security boundaries worth preserving:

- Credential discovery stays outside SwiftUI views.
- Bearer tokens are used only by provider-specific clients.
- Network and subprocess calls use explicit timeouts.
- Provider error bodies are truncated before display.
- Xcode previews use sample data only.

The app target currently has the macOS app sandbox disabled because the trackers
need local auth-file access, subprocess credential lookup, and remote quota
requests. If sandboxing is re-enabled, retest Keychain access, Cursor SQLite
access, Codex auth-file access, and network calls.

## Requirements

- macOS 26.5 or newer target SDK/runtime.
- Xcode 26.6 or compatible version for the current project format.
- A signed-in Codex CLI or Cursor install for live tracker data.

## Build And Verify

Open `BorderCollie.xcodeproj` in Xcode and run the `BorderCollie` scheme.

For non-launching command-line verification, use:

```sh
xcodebuild build-for-testing \
  -project BorderCollie.xcodeproj \
  -scheme BorderCollie \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/BorderCollieDerivedDataBuild \
  CODE_SIGNING_ALLOWED=NO
```

Avoid direct app-hosted `xcodebuild test` unless you specifically need it and
are prepared for the app UI to launch.

## Project Layout

```text
BorderCollie/
  BorderCollieApp.swift          App entry point
  ContentView.swift              Root navigation
  UsageTrackerView.swift         Shared tracker UI
  UsageTrackerViewModel.swift    Refresh lifecycle and timeout handling
  UsageTrackingService.swift     Shared service and HTTP protocols
  Codex*.swift                   Codex credential, API, display, and view code
  Cursor*.swift                  Cursor credential, API, display, and view code
BorderCollieTests/
  BorderCollieTests.swift        Swift Testing coverage
docs/
  tracker_design.md              Architecture guide for adding trackers
```

## Development Notes

- Keep provider credential lookup isolated from SwiftUI.
- Store provider-reported used percentage in `QuotaTier.utilization`; convert to
  remaining percentage only in display code.
- Keep auto refresh fixed at 30 seconds unless the product standard changes.
- Keep previews deterministic and offline.
- Add tests for new credential parsing, response normalization, display labels,
  and error mapping when adding another tracker.

Read `docs/tracker_design.md` before adding future trackers.

## License

BorderCollie is released under the MIT License. See `LICENSE` for details.
