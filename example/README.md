# Riverpod DevTools Example App

This is a standalone example application demonstrating the usage of [riverpod_devtools](https://pub.dev/packages/riverpod_devtools).

## Features

This example showcases:
- Provider lifecycle tracking (init/dispose)
- Complex state management with lists
- Async state handling
- **Static dependency analysis** with interactive dependency graph visualization
- **Performance stats** (update rate, async load duration, churn)
- Stress testing with large event logs

## Supported Platforms

- iOS
- Android
- Web

## Getting Started

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Generate Dependency Metadata (Required)

To enable the dependency graph feature in DevTools, run the static analyzer:

```bash
# From the example directory
dart run riverpod_devtools:analyze

# Or use watch mode for automatic re-analysis during development
dart run riverpod_devtools:analyze --watch
```

This will generate `lib/riverpod_dependencies.json` with static dependency information for all providers.

A pre-generated `lib/riverpod_dependencies.json` is committed so the example builds and shows the dependency graph out of the box — re-run the analyzer (or use `--watch`) after you change any provider.

### 3. Run the App

```bash
flutter run
```

## Using DevTools

1. Run the app
2. Open Flutter DevTools (click the link in the console)
3. Navigate to the **"riverpod_devtools"** tab
4. Select any provider to view:
   - **Current state** with JSON tree view
   - **Dependencies** (Depends On / Used By) when static analysis is configured
   - **Event history** (add, update, dispose)
5. Interact with the app to see provider events in real-time

### Dependency Graph Features

The **Dependencies Demo** page demonstrates:
- Simple dependency chains (`authTokenProvider` → `userIdProvider`)
- Multiple dependencies (`userProfileProvider` depends on both `userNameProvider` and `userEmailProvider`)
- Transitive dependencies (`tripleCounterProvider` → `doubleCounterProvider` → `counterProvider`)

In DevTools, you'll see:
- **Depends On / Used By**: When static analysis is loaded and provider names match
- **Provider Name Mismatch**: When JSON is loaded but the provider name does not match
- **Static Analysis Required**: When the analyzer has not been run or JSON is not loaded

## Project Structure

```
lib/
├── main.dart                      # App entry point with JSON loading
├── riverpod_dependencies.json    # Generated: static dependency metadata
└── pages/
    ├── dependencies_page.dart    # Demonstrates dependency chains
    ├── lifecycle_page.dart       # Provider lifecycle tracking
    ├── async_page.dart           # Async state handling
    ├── collections_page.dart     # Complex collections (Set/Map/Nested)
    ├── performance_page.dart     # Stress testing with large data
    ├── custom_class_page.dart    # Custom class serialization
    └── todo_page.dart            # Todo list state management
```

## Troubleshooting

### Dependencies not showing in DevTools

If you see **Static Analysis Required** in Provider Details:

1. Ensure you ran the analyzer: `dart run riverpod_devtools:analyze`
2. Check that `lib/riverpod_dependencies.json` exists
3. Verify the JSON file is listed in `pubspec.yaml` assets
4. Verify JSON loading is called in `main()` before `runApp()`
5. Hot restart the app to reload the JSON

### Analysis fails

Make sure you're running the command from the example directory:

```bash
cd /path/to/riverpod_devtools/example
dart run riverpod_devtools:analyze
```

## Learn More

- [Riverpod Documentation](https://riverpod.dev)
- [Flutter DevTools Documentation](https://flutter.dev/devtools)
- [riverpod_devtools Package](https://pub.dev/packages/riverpod_devtools)
- [Main Project README](../packages/riverpod_devtools/README.md)
