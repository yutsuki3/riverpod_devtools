## Unreleased

- **Performance diagnostics: update frequency, async load duration, churn** ([#56](https://github.com/yutsuki3/riverpod_devtools/issues/56)):
    - New "Stats" tab in the DevTools extension: a sortable table of per-provider update count (total and in the last 10s), async load duration (min/avg/max of observed `loading`→`data`/`error` transitions), and dispose→re-create churn count, aggregated from the event log. Click a column header to sort; click a row to jump to that provider in the Inspector view.
    - Providers exceeding a threshold (>10 updates/sec sustained, or a load over 2s) get a warning badge in the Stats table and in the provider list.
    - New `get_provider_stats` MCP tool (and `GET /stats` on the local HTTP endpoint) so AI tools can be asked "which provider is rebuilding excessively?" without pulling and analyzing the full event log.
- **Interactive dependency graph view** ([#55](https://github.com/yutsuki3/riverpod_devtools/issues/55)):
    - New Inspector / Graph view switcher in the DevTools extension. The Graph view renders providers as a layered DAG (dependencies left, dependents right) with pan/zoom, edge styling per dependency kind (`watch` solid, `read` dashed, `listen` dotted), status coloring (active / disposed / failed with error badge), and dependency-cycle highlighting.
    - Clicking a node selects it (Provider Details shown alongside, including Invalidate/Refresh) and focuses the graph on its transitive dependencies and dependents in one gesture; "Show all" returns to the full graph. The provider search query dims non-matching nodes, and an on-screen legend explains the edge styles, node states, and gestures.
    - The observer now attaches `dependencyDetails` (kind + source location per dependency, from the static-analysis registry) to `provider_added` events so the extension can style edges.
- **State operations: invalidate / refresh from DevTools and MCP** ([#54](https://github.com/yutsuki3/riverpod_devtools/issues/54)):
    - The observer now tracks live provider instances (with their owning container) and can execute `invalidate` / `refresh` commands against them. Debug mode only.
    - New `ext.riverpod_devtools.command` service extension so the DevTools extension can run commands on any platform; the DevTools Provider Details panel gains **Invalidate** and **Refresh** buttons (disabled for disposed providers, with inline success/error feedback).
    - New `invalidate_provider` MCP tool (and `POST /commands` on the local HTTP endpoint) so AI tools can reproduce flows end-to-end: clear logs → invalidate → read logs. The tool description flags it as a state-mutating action.
- **MCP tool expansion** ([#53](https://github.com/yutsuki3/riverpod_devtools/issues/53)):
    - New `get_provider_state` MCP tool (and `GET /providers` on the local HTTP endpoint): a current-state snapshot of live providers — name, status (`active`/`failed`), latest value, error details when failed, and last-update timestamp — so AI tools no longer need to replay the event log to answer "what is the current state". Disposed providers are evicted from the snapshot; `clear_riverpod_logs` does not affect it.
    - New `get_dependency_graph` MCP tool (and `GET /graph`): nodes with runtime status merged in, plus directed dependency edges (`watch`/`read`/`listen`, with source locations) from the static-analysis registry. An optional `provider` parameter returns only that provider's transitive dependencies and dependents.
- **First-class error capture** ([#52](https://github.com/yutsuki3/riverpod_devtools/issues/52)):
    - The observer now implements `providerDidFail` (Riverpod 2.x and 3.x signatures) and emits a `provider_failed` event carrying the error's runtime type, message (capped at 2000 chars), and a trimmed stack trace (Riverpod-internal frames dropped, max 20 frames).
    - DevTools extension: failed events appear in the Event Log with a red FAILED badge and expandable error details; providers currently in a failed state show an error badge in the provider list and a dedicated "Error" section (message + collapsible stack trace + copy button) in Provider Details. The error clears when the provider next updates successfully.
    - MCP / HTTP endpoint: `get_riverpod_logs` and `GET /logs` accept a new `type` filter (e.g. `provider_failed` to fetch only errors).
- **Causality chain (why did this provider rebuild?)** ([#51](https://github.com/yutsuki3/riverpod_devtools/issues/51)):
    - Every observer event now carries a monotonic `seq` number for unambiguous ordering (timestamps collide within a millisecond).
    - `provider_updated` events now carry `triggeredBy` — the dependency update(s) that likely caused the recomputation, inferred from the static dependency graph plus temporal proximity and marked `triggerConfidence: "inferred"`.
    - DevTools extension: update cascades are rendered as indented chains in the Event Log, with a clickable "caused by X" chip that selects and flashes the triggering provider; the Provider Details "Last Update" section also shows the trigger.
    - MCP: the new fields flow through `get_riverpod_logs` automatically, so AI tools can trace update cascades.
- **MCP**:
    - `get_riverpod_logs` now accepts optional `limit` (most recent N events) and `provider` (exact provider name) parameters, so AI tools can fetch only the relevant slice of the buffer instead of up to 1000 full events. The local HTTP endpoint (`GET /logs`) accepts the same values as query parameters.
- **Performance**:
    - `RiverpodDevToolsObserver` is now near-zero overhead when nothing can consume its events (release/profile builds without a DevTools client attached): value serialization is skipped entirely instead of running on every provider change.
    - Value serialization uses identity-based cycle detection, avoiding deep user-defined `==`/`hashCode` calls (e.g. freezed models with large collections) on every event, and no longer builds an object's `toString()` when it serializes via `toJson()`.
    - The Riverpod 2.x/3.x API probe in the observer is cached, so it no longer throws and catches a `NoSuchMethodError` on every event on Riverpod 2.x.
    - The MCP event buffer is now a ring buffer with O(1) eviction (previously each event shifted the whole 1000-entry list once full).
    - Static dependency names are cached per provider in the registry instead of being rebuilt from metadata on every provider event.
    - DevTools extension: the filtered provider/event lists are memoized per state change instead of being re-filtered and re-sorted on every widget rebuild, and appending an event no longer copies the event list twice.
    - DevTools extension: "Used By" is now answered from a reverse-dependency index rebuilt only when the provider map changes (previously a full providers × dependencies scan on every detail-panel rebuild), the "Last Update" section reads the provider's latest event in O(1) instead of filtering the whole event log, and event de-duplication no longer schedules a Timer per incoming event.
- **Fixes**:
    - `AsyncValue` states (`data`/`loading`/`error`) are shown again in the extension UI — the `asyncState` marker was unreachable in serialization because the structured `toString()` parser returned first.
    - DevTools extension: the Event Log "Clear All" button now actually clears the log (it was a no-op).
    - DevTools extension: providers that are disposed and later re-created are no longer evicted from the provider list by the disposed-provider cleanup.
    - DevTools extension: event IDs are now unique even when a provider emits multiple events within the same millisecond, preventing duplicate-key errors in the event list.
- **Dev**:
    - Widened the extension package's `vm_service` constraint to `>=14.0.0 <16.0.0` so it resolves with Flutter >=3.32 (which pins `vm_service` 15.0.0).

## 0.6.2

- **Docs**:
    - Highlighted MCP support in the README (badge, tagline, Features list, dedicated section) and pub.dev metadata (`description`, `topics`) — no code changes.

## 0.6.1

- **Dependencies**:
    - Widened the `analyzer` constraint from `^6.0.0` to `>=6.0.0 <15.0.0` to cover the current latest `analyzer` release and improve the pub.dev "supports latest dependencies" score.
- **Example**:
    - Replaced `StateProvider` with `NotifierProvider`/`Notifier` in the bundled example so it keeps compiling across the full supported `flutter_riverpod` range (`2.3.0`–`4.0.0`), including when resolved to Riverpod 3.x.

## 0.6.0

- **MCP Integration**:
    - Added a bundled MCP server (`dart run riverpod_devtools:riverpod_devtools_mcp`) so AI tools like Claude Code can read live Riverpod provider event logs from a running app. See [MCP.md](MCP.md).
    - `RiverpodDevToolsObserver` now starts a local, debug-only HTTP server (`localhost:8788`) that the MCP server reads from.
    - HTTP server start failures are now logged via `dart:developer` instead of being silently swallowed.
- **Breaking**:
    - Raised minimum SDKs to Dart `^3.7.0` and Flutter `>=3.32.0` to accommodate the MCP server's `dart_mcp` dependency. Stay on `riverpod_devtools: ^0.5.0` if you can't upgrade yet.

## 0.5.0

- **Static Dependency Analysis (CLI)**:
    - Added `dart run riverpod_devtools:analyze` to generate `lib/riverpod_dependencies.json`.
    - Added AST-based provider dependency extraction (watch/read/listen) with source locations.
    - Added `RiverpodDevToolsRegistry` for loading static metadata in your app.
    - **Breaking**: Removed runtime-based dependency detection; dependencies now come from static analysis only.
- **DevTools UI**:
    - Updated Provider Details for the static-analysis workflow (setup instructions, provider name mismatch handling).
    - Redesigned caution messages as collapsible dropdowns.
    - Added selectable text and copy buttons in the extension UI.
    - Refactored the extension codebase into modular files for maintainability.
- **Stability**:
    - Improved serialization error handling and recursion safety.
    - Fixed provider type detection order in the CLI analyzer.
    - Internal refactor: `ListUtils`, deduplicated observer event payload building.
- **Documentation & pub.dev**:
    - Added TROUBLESHOOTING guide and updated README for CLI setup.
    - Added pubspec metadata (platforms, topics, homepage, screenshots).
- **Example**:
    - Updated example apps for CLI-based static analysis.
    - Removed debug print statements on JSON load failure.

## 0.4.4

- **Improved Data Serialization**:
    - Significantly improved serialization for custom classes by parsing structured `toString()` output.
    - Fixed issues where collection string representations were misinterpreted as custom classes.
    - Enhanced recursive item serialization for Lists, Maps, and Sets.
- **Tree View & Event Log UI**:
    - Added support for the `entity` metadata key in the JSON tree view, allowing for better representation of complex objects.
    - Improved value formatting in the Event Log.
- **Stability**:
    - Refined internal parsing logic to avoid misidentification of data types.

## 0.4.3

- **UI Improvements (Provider Details)**:
    - Improved dependency chip layout for better readability.
- **Tree View Refinements**:
    - JSON Tree View now collapses by default to reduce noise.
    - Refined JSON object unwrapping to prioritize meaningful data (prioritize `entries` over `string` representation).
    - Filtered out internal metadata keys from the tree view display.
- **Event Log Enhancements**:
    - Added support for collapsible long strings in the Event Log.
    - Improved overall readability of event details.
- **Stability & Performance**:
    - Fixed memory leaks by ensuring disposed providers and empty event lists are properly cleaned up.

## 0.4.2

- Fixed missing DevTools extension build files (index.html and other assets) that prevented the extension from loading properly

## 0.4.1

- Fixed devtools config.yaml version mismatch (was 0.3.0, now matches package version 0.4.1)

## 0.4.0

- Added Learning-based Dependency Tracking to support dependency visualization in Riverpod 3.x
- Support for Light Mode UI with VS Code-inspired color themes
- Improved Event Log UI with hierarchical grouping (e.g., `Recomputed` status for invalidation waves)
- Added new event types: `invalidate`, `refresh`, `rebuild`, `dependencyChangeEvent`, and `asyncComplete`
- Optimized data serialization and display:
    - Added type labels (e.g., `String`, `int`) in Tree View
    - Fixed Map/Set display to unwrap internal metadata for better readability
    - Added "Show more" button for large collections
    - Implemented caching for value string conversions
- Enhanced Event Log filtering with multi-selection and "Show All" toggle
- Expanded `flutter_riverpod` dependency range to `>=2.3.0 <4.0.0`
- Updated example app with comprehensive demo pages for different provider types

## 0.3.0

- Refresh provider list UI and add filtering feature
- Add example pages (`collections`, `lifecycle`, `todo`, `async`) and new demos for Set, Map, and nested collections

## 0.2.0

- **Breaking**: Updated to support both Riverpod 2.x and 3.x (`flutter_riverpod: '>=2.6.1 <4.0.0'`)
- Updated `RiverpodDevToolsObserver` to handle API changes in Riverpod 3.0
- Improved compatibility layer for seamless migration between Riverpod versions
- Fixed pub.dev warnings about outdated dependencies

## 0.1.0

- Initial release of access to the Riverpod DevTools extension.
- Added `RiverpodDevToolsObserver` to track provider events.
