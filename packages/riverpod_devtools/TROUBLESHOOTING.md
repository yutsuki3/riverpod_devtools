# Troubleshooting Guide - Riverpod DevTools

## Static Dependency Analysis Issues

### Analyzer fails to run

**Symptoms**: `dart run riverpod_devtools:analyze` fails with errors.

**Possible Causes**:
- Running from wrong directory
- No `lib/` directory found
- Syntax errors in Dart files

**Solutions**:

1. Ensure you're in the project root directory (where `pubspec.yaml` is located):
   ```bash
   cd /path/to/your/project
   dart run riverpod_devtools:analyze
   ```

2. Check that `lib/` directory exists and contains `.dart` files

3. Fix any Dart syntax errors in your code first

4. Run flutter analyze to check for issues:
   ```bash
   flutter analyze
   ```

### Dependencies not detected (empty list)

**Symptoms**: Generated JSON file exists but shows no dependencies.

**Possible Causes**:
- Non-standard `ref` usage (e.g., assigned to variable)
- Complex provider patterns the analyzer doesn't recognize

**Diagnostic Steps**:

1. Check generated JSON file content:
   ```bash
   cat lib/riverpod_dependencies.json
   ```

2. Verify ref usage is direct:
   ```dart
   // ✅ Detected
   final provider = Provider((ref) {
     return ref.watch(counterProvider);
   });

   // ❌ Not detected
   final provider = Provider((ref) {
     final r = ref;
     return r.watch(counterProvider);
   });
   ```

3. The analyzer detects dependencies in:
   - Provider callbacks: `Provider((ref) => ref.watch(...))`
   - Notifier classes: `class MyNotifier extends Notifier { ... }`
   - All standard provider types (Provider, StateProvider, FutureProvider, etc.)

### Dependencies not showing in DevTools ("Static Analysis Required")

**Symptoms**: Provider Details shows **Static Analysis Required** instead of Depends On / Used By.

**Possible Causes**:
- Analyzer has not been run
- JSON file not loaded in `main()`
- JSON file not declared in `pubspec.yaml` assets

**Solutions**:

1. Run the analyzer:
   ```bash
   dart run riverpod_devtools:analyze
   ```

2. Verify JSON loading in `main()` (must run before `runApp()`):
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();

     final jsonString = await rootBundle.loadString(
       'lib/riverpod_dependencies.json',
     );
     RiverpodDevToolsRegistry.instance.loadFromJson(jsonString);

     runApp(...);
   }
   ```

3. Add the JSON file to `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - lib/riverpod_dependencies.json
   ```

4. Hot **restart** the app (not hot reload) after regenerating JSON

### Provider Name Mismatch warning

**Symptoms**: Provider Details shows **Provider Name Mismatch** instead of dependency lists.

**Possible Causes**:
- JSON was loaded, but the runtime provider name does not exactly match any entry in the JSON file (case-sensitive)
- Analyzer was run against a different codebase than the running app

**Solutions**:

1. Check the provider variable name in your code matches the JSON entry:
   ```dart
   final myProvider = Provider(...);  // Name must be "myProvider"
   ```

2. Re-run the analyzer after renaming providers:
   ```bash
   dart run riverpod_devtools:analyze
   ```

3. Debug registered provider names:
   ```dart
   print(RiverpodDevToolsRegistry.instance.allProviderNames);
   ```

## General DevTools Issues

### Extension not showing in DevTools

**Symptoms**: "riverpod_devtools" tab not visible in Flutter DevTools.

**Solutions**:

1. Ensure you've added the observer:
   ```dart
   ProviderScope(
     observers: [RiverpodDevToolsObserver()],
     child: MyApp(),
   )
   ```

2. Restart DevTools:
   - Close DevTools
   - Hot restart the app
   - Reopen DevTools

3. Check DevTools version:
   ```bash
   flutter --version
   # Ensure using Flutter 3.0 or later
   ```

### No events appearing in DevTools

**Symptoms**: Extension loads but shows no provider events.

**Solutions**:

1. Verify observer is in ProviderScope
2. Trigger provider interactions (navigate, tap buttons)
3. Check console for errors
4. Ensure app is in debug mode (not release)

## MCP Issues

### AI tool reports "No running Flutter app ... was found on ports 8788–8797"

The MCP server probes `localhost:8788`–`8797` and found nothing. Check, in order:

1. The Flutter app is running in **debug mode** (`flutter run`). The HTTP endpoint never starts in profile/release builds, and not on web.
2. `RiverpodDevToolsObserver()` is registered in `ProviderScope(observers: [...])`.
3. You're on a **real device or Android emulator** — those have their own network namespace, so forward the port first: `adb forward tcp:8788 tcp:8788` (Android) or `iproxy` (iOS device). Desktop apps and the iOS Simulator need no forwarding.

### The MCP server times out on its very first launch

`dart run riverpod_devtools:riverpod_devtools_mcp` compiles the server the first time it runs (~10–20 s), which can exceed an MCP client's startup timeout. Retry / restart the AI tool — subsequent launches reuse the compiled snapshot and start in well under a second. The snapshot is rebuilt after `flutter pub get` or dependency changes.

### `get_dependency_graph` returns empty `edges`

If the response contains an `edgesNote`, follow it: it means static dependency data isn't loaded (run `dart run riverpod_devtools:analyze`, load `lib/riverpod_dependencies.json` in `main()`, add it to the pubspec assets, hot-restart) or the loaded data matches no running provider by name (re-run the analyzer). Without an `edgesNote`, the running providers genuinely have no static dependencies.

### `invalidate_provider` / `set_provider_value` is rejected with `ambiguous: true`

Several live providers share that display name. The error lists candidate `instanceId`s — call the tool again passing one of them as `provider`. You can see each provider's `instanceId` (and a `nameIsUnique` flag) in `get_provider_state`.

### `set_provider_value` returns `supported: false`

By design, v1 only writes **primitive** values (int/double/bool/String/null) into providers with a writable notifier (`StateProvider`, `NotifierProvider`). Plain / `FutureProvider` / `StreamProvider` providers, and providers whose state is an object or `AsyncValue`, cannot be set — use `invalidate_provider` instead.

### Two apps are running and tools hit the wrong one

Call `list_riverpod_apps` and pass the chosen `port` to every other tool. Each debug app binds the first free port in `8788`–`8797`.

## JSON File Issues

### JSON file not found at runtime

**Symptoms**: App crashes with "Unable to load asset: lib/riverpod_dependencies.json"

**Solutions**:

1. Ensure the analyzer has been run:
   ```bash
   dart run riverpod_devtools:analyze
   ```

2. Verify the file exists:
   ```bash
   ls lib/riverpod_dependencies.json
   ```

3. Declare the file in `pubspec.yaml` assets:
   ```yaml
   flutter:
     assets:
       - lib/riverpod_dependencies.json
   ```

### JSON file outdated

**Symptoms**: Changes to providers not reflected in DevTools

**Solutions**:

1. Re-run the analyzer after making changes:
   ```bash
   dart run riverpod_devtools:analyze
   ```

2. Consider using watch mode during development:
   ```bash
   dart run riverpod_devtools:analyze --watch
   ```

3. Hot restart (not hot reload) after regenerating JSON

## Performance Issues

### Slow analysis times

**Symptoms**: `dart run riverpod_devtools:analyze` takes a long time.

**Solutions**:

1. The analyzer scans all `.dart` files in `lib/`. For large projects, this may take a few seconds.

2. Use watch mode during development to avoid re-running manually:
   ```bash
   dart run riverpod_devtools:analyze --watch
   ```

3. The generated JSON file is small and loads quickly at app startup.

### DevTools UI lag with many providers

**Symptoms**: Extension UI becomes slow with many providers.

**Solutions**:

1. Use provider search/filter
2. Select specific providers instead of viewing all
3. Clear event log periodically
4. Check for memory leaks in app (disposed providers)

## Getting Help

If you encounter issues not covered here:

1. Check existing issues: [GitHub Issues](https://github.com/yutsuki3/riverpod_devtools/issues)
2. Provide the following information when reporting:
   - Flutter version (`flutter --version`)
   - Riverpod version
   - `riverpod_devtools` version
   - Minimal reproduction code
   - Generated `lib/riverpod_dependencies.json` (if relevant)
   - Console error messages

## Additional Resources

- [Riverpod Documentation](https://riverpod.dev)
- [DevTools Documentation](https://flutter.dev/devtools)
