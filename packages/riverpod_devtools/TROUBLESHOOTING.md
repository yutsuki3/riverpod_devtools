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

### Static dependencies not used (always shows "Runtime Detection")

**Symptoms**: `dependenciesSource` is always `'runtime'` in DevTools UI.

**Possible Causes**:
- JSON file not loaded
- JSON file not included in app bundle
- Provider name mismatch between JSON and runtime

**Solutions**:

1. Verify JSON loading in `main()`:
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();

     // This MUST be called before runApp()
     final jsonString = await rootBundle.loadString(
       'lib/riverpod_dependencies.json',
     );
     RiverpodDevToolsRegistry.instance.loadFromJson(jsonString);

     runApp(...);
   }
   ```

2. Ensure JSON file is in your app bundle (check `lib/riverpod_dependencies.json` exists)

3. Check provider name consistency:
   ```dart
   // Provider variable name = Registry key = provider.name
   final myProvider = Provider(...);  // Name: "myProvider"
   ```

4. Debug registry contents:
   ```dart
   void main() async {
     WidgetsFlutterBinding.ensureInitialized();

     final jsonString = await rootBundle.loadString(
       'lib/riverpod_dependencies.json',
     );
     RiverpodDevToolsRegistry.instance.loadFromJson(jsonString);

     // Debug: Print registered providers
     print('Registered providers: ${RiverpodDevToolsRegistry.instance.allProviderNames}');

     runApp(...);
   }
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

### Dependencies show false positives (Runtime Detection)

**Symptoms**: Runtime detection shows incorrect dependencies.

**Explanation**: Runtime detection uses timing-based heuristics (100ms window) which can produce false positives.

**Solutions**:

1. Enable static analysis (see README setup)
2. Accept runtime detection limitations for dynamic providers
3. Use static analysis as primary source, runtime as fallback

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

3. The JSON file is automatically included in your app bundle (any file in `lib/` is included)

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
   - Generated `.g.dart` file (if relevant)
   - Console error messages

## Additional Resources

- [Riverpod Documentation](https://riverpod.dev)
- [build_runner Documentation](https://pub.dev/packages/build_runner)
- [DevTools Documentation](https://flutter.dev/devtools)
