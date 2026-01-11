# Riverpod DevTools Example

This example demonstrates how to use `riverpod_devtools` with static dependency analysis enabled via the CLI tool.

## Features Demonstrated

This example showcases:

- ✅ **Static Dependency Analysis** using the CLI tool
- ✅ **Multiple provider types** (StateProvider, Provider, FutureProvider)
- ✅ **Different dependency patterns** (watch, read)
- ✅ **JSON-based metadata** with accurate dependency detection
- ✅ **No part directives needed** - clean code approach

## Project Structure

```
lib/
├── main.dart                      # App entry point with JSON loading
├── providers.dart                 # Provider definitions (no part directives!)
└── riverpod_dependencies.json    # Generated: dependency metadata
```

## Providers in this Example

### Simple Providers (No Dependencies)

```dart
// lib/main.dart
final counterProvider = StateProvider<int>((ref) => 0);
final nameProvider = StateProvider<String>((ref) => 'Flutter');
```

### Providers with Dependencies

```dart
// lib/providers.dart

// Uses ref.watch
final doubleCounterProvider = Provider<int>((ref) {
  final count = ref.watch(counterProvider);  // ← Detected!
  return count * 2;
});

// Uses multiple ref.watch
final displayTextProvider = Provider<String>((ref) {
  final count = ref.watch(counterProvider);  // ← Detected!
  final name = ref.watch(nameProvider);      // ← Detected!
  return '$name: $count';
});

// Uses ref.read
final manualCounterProvider = Provider<int>((ref) {
  final count = ref.read(counterProvider);  // ← Detected!
  return count + 10;
});

// Async provider with dependencies
final asyncDataProvider = FutureProvider<String>((ref) async {
  final name = ref.watch(nameProvider);  // ← Detected!
  await Future.delayed(const Duration(milliseconds: 100));
  return 'Async: $name';
});
```

## How to Run

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Generate Static Dependencies

```bash
# One-time generation
dart run riverpod_devtools:analyze

# Or use watch mode (recommended during development)
dart run riverpod_devtools:analyze --watch
```

This will generate:
- `lib/riverpod_dependencies.json` - Single JSON file with all dependency metadata

### 3. Run the App

```bash
flutter run
```

### 4. Open DevTools

1. Click the DevTools link in the console
2. Navigate to the "riverpod_devtools" tab
3. Select a provider to view its details
4. Check the **Dependencies** section - it should show:
   - **Static Analysis** (green) for all analyzed providers
   - **Warning** (orange) if CLI tool hasn't been run

## What to Look For in DevTools UI

**For providers with static analysis:**
```
Dependencies
┌────────────────────────────────────────┐
│ ✅ Static Analysis: Dependencies      │
│    detected from source code          │
└────────────────────────────────────────┘
Depends On:
  [counterProvider] [nameProvider]
```

**If CLI tool hasn't been run:**
```
Dependencies
┌────────────────────────────────────────┐
│ ⚠️  No dependency data available.     │
│    Run: dart run riverpod_devtools:analyze
└────────────────────────────────────────┘
Depends On:
  Run CLI tool to analyze dependencies
```

## Testing the Dependencies

1. **Tap the + button** to increment the counter
   - `doubleCounterProvider` should update (depends on counterProvider)
   - `displayTextProvider` should update (depends on counterProvider)

2. **Tap "Change Name"** button
   - `displayTextProvider` should update (depends on nameProvider)
   - `asyncDataProvider` should reload (depends on nameProvider)

3. **In DevTools**, observe:
   - Event log showing provider updates
   - Dependency graph showing relationships
   - Green indicators for static analysis

## Troubleshooting

### Dependencies not detected

- Ensure the analyzer has been executed: `dart run riverpod_devtools:analyze`
- Check that `lib/riverpod_dependencies.json` exists
- Verify JSON loading is called in `main()` (see `main.dart` lines 13-25)
- Check that JSON file is listed in `pubspec.yaml` assets
- See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for more help

### Analysis fails

```bash
# Ensure you're in the example directory
cd /path/to/riverpod_devtools/packages/riverpod_devtools/example
dart run riverpod_devtools:analyze
```

## Key Differences from build_runner Approach

| Aspect | CLI Tool (Current) | build_runner (Old) |
|--------|-------------------|-------------------|
| **Setup** | Run CLI tool once | Add part directives to all files |
| **Files Modified** | 1 (main.dart only) | N+1 (all provider files + main) |
| **Generated Output** | Single JSON file | Multiple .g.dart files |
| **Code Cleanliness** | No part directives | Part directives everywhere |
| **Command** | `dart run riverpod_devtools:analyze` | `dart run build_runner build` |

## Learning Resources

- [Riverpod Documentation](https://riverpod.dev)
- [DevTools Documentation](https://flutter.dev/devtools)
- [Project README](../README.md)
- [Troubleshooting Guide](../TROUBLESHOOTING.md)
- [CLI Tool Migration Guide](../../../CLI_TOOL_MIGRATION.md)
