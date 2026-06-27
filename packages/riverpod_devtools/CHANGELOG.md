## 0.6.1

- **Dependencies**:
    - Widened the `analyzer` constraint from `^6.0.0` to `>=6.0.0 <15.0.0` to cover the current latest `analyzer` release and improve the pub.dev "supports latest dependencies" score.

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
