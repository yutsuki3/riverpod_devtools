# riverpod_devtools

[![pub package](https://img.shields.io/pub/v/riverpod_devtools.svg)](https://pub.dev/packages/riverpod_devtools)

A [DevTools](https://flutter.dev/devtools) extension for [Riverpod](https://riverpod.dev) - inspect and monitor your providers in real-time.

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/screenshot_044.png" width="100%" alt="Riverpod DevTools Demo" />

## Features

- **Provider Graph**: Visualize the relationships between your providers (Beta: Learning-based tracking).
- **State Inspector**: View the current state of your providers with type labels and optimized display.
- **Event Log**: Track provider lifecycle events with hierarchical grouping and sub-events.
- **Stack Trace Tracking** (Optional): See exactly where provider updates originated with file paths, line numbers, and full call chains.
- **Light Mode Support**: Seamlessly switch between light and dark themes.

## Getting started

1.  Add `riverpod_devtools` to your `pubspec.yaml`:

    Run the command:

    ```bash
    flutter pub add riverpod_devtools
    ```

    Or manually add it:

    ```yaml
    dependencies:
      riverpod_devtools: ^0.4.4
      flutter_riverpod: '>=2.3.0 <4.0.0'
    ```

    **Note:** This package supports both Riverpod 2.x and 3.x.

2.  Add `RiverpodDevToolsObserver` to your `ProviderScope`:

    While the DevTools extension is automatically detected, you **must** add the observer to enable communication between your app and the DevTools.

    ```dart
    import 'package:flutter_riverpod/flutter_riverpod.dart';
    import 'package:riverpod_devtools/riverpod_devtools.dart';

    void main() {
      runApp(
        ProviderScope(
          observers: [
            RiverpodDevToolsObserver(),
          ],
          child: MyApp(),
        ),
      );
    }
    ```

## Usage

1.  Run your Flutter app.
2.  Open semantic DevTools (open the debugger).
3.  Look for the "riverpod_devtools" tab in DevTools.
4.  Interact with your app and watch the events and state updates in the DevTools tab.

## Stack Trace Tracking (Optional)

Enable stack trace tracking to see exactly where provider updates are triggered in your code:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_devtools/riverpod_devtools.dart';

void main() {
  runApp(
    ProviderScope(
      observers: [
        RiverpodDevToolsObserver(
          stackTraceConfig: StackTraceConfig.forPackage('my_app'),
        ),
      ],
      child: MyApp(),
    ),
  );
}
```

### Benefits

- **Precise Debugging**: See the exact file, line number, and function that triggered a provider update
- **Full Call Chain**: View the complete call stack leading to the update
- **Filter Framework Code**: Automatically excludes Flutter and Riverpod framework code
- **Async Support**: Works with async providers through stack trace caching

### Configuration Options

```dart
// Simple configuration (recommended)
StackTraceConfig.forPackage('my_app')

// Advanced configuration
StackTraceConfig(
  enabled: true,
  maxCallChainDepth: 10,                      // Max stack frames to capture
  packagePrefixes: ['package:my_app/'],       // Only show code from these packages
  ignoredPackagePrefixes: [                   // Additional packages to ignore
    'package:my_library/',
  ],
  ignoredFilePatterns: [                      // File patterns to ignore
    '.g.dart',
    '.freezed.dart',
  ],
  maxStackCacheSize: 100,                     // Max cached stacks for async providers
  stackCacheExpirationSeconds: 60,            // Cache expiration time
)
```

### Production Considerations

Stack trace tracking adds a small performance overhead. Disable it in production:

```dart
import 'package:flutter/foundation.dart';

RiverpodDevToolsObserver(
  stackTraceConfig: kDebugMode
      ? StackTraceConfig.forPackage('my_app')
      : null,
)
```

### Attribution

Stack trace tracking concept inspired by [riverpod_devtools_tracker](https://github.com/weitsai/riverpod_devtools_tracker) by [@weitsai](https://github.com/weitsai).

## Additional information

-   **Repository**: [https://github.com/yutsuki3/riverpod_devtools](https://github.com/yutsuki3/riverpod_devtools)
-   **Issues**: [https://github.com/yutsuki3/riverpod_devtools/issues](https://github.com/yutsuki3/riverpod_devtools/issues)

Contributions are welcome!

## License

This package is released under the MIT License. See [LICENSE](LICENSE) for details.
