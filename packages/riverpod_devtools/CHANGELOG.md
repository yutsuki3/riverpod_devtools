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
