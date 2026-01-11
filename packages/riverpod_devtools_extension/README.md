# riverpod_devtools_extension

**Internal package - DevTools extension UI source code**

This package contains the Flutter web app that powers the Riverpod DevTools extension UI. This is an internal development package and is **not published to pub.dev**.

## Purpose

This package builds the DevTools extension interface that users see when inspecting Riverpod providers. The built output is copied to `packages/riverpod_devtools/extension/devtools/build/` and published as part of the main `riverpod_devtools` package.

## For Contributors

### Building the Extension

```bash
# From this directory
flutter pub get
flutter build web --release

# The output in build/web/ should be copied to:
# ../riverpod_devtools/extension/devtools/build/
```

### Development

```bash
# Run in debug mode for development
flutter run -d chrome
```

### Features

The extension UI provides:

- **Provider List**: Real-time list of all active providers with search and filtering
- **State Inspector**: JSON tree view of provider values with syntax highlighting
- **Event Log**: Timeline of provider lifecycle events (add, update, dispose)
- **Dependencies View**: Visualize provider dependencies via static analysis
- **Theme Support**: Automatic light/dark mode based on DevTools theme

## Architecture

- **main.dart**: Main extension app with all UI components
- Communication with the app happens via DevTools extension API and VM service events
- Events are posted from the app using `RiverpodDevToolsObserver` in the main package

## Related Packages

- [riverpod_devtools](../riverpod_devtools/): Main package (published to pub.dev)
- Parent repository: [yutsuki3/riverpod_devtools](https://github.com/yutsuki3/riverpod_devtools)
