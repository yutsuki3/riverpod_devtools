import 'dart:async' show unawaited;
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'http_server_support.dart';
import 'static_dependencies.dart';
import 'utils/serialization.dart';

/// A [ProviderObserver] that sends Riverpod events to the Flutter DevTools extension.
///
/// This observer monitors the lifecycle of all providers (add, update, dispose)
/// and posts events to the developer log, which the Riverpod DevTools extension listens to.
/// In debug mode on native platforms, it also starts a local HTTP server on port 8788
/// so that MCP tools can read the event log.
///
/// **Important**: This observer requires static dependency analysis via the CLI tool.
/// Run `dart run riverpod_devtools:analyze` to generate dependency metadata.
///
/// Usage:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // Load static dependencies
///   try {
///     final jsonString = await rootBundle.loadString('lib/riverpod_dependencies.json');
///     RiverpodDevToolsRegistry.instance.loadFromJson(jsonString);
///   } catch (_) {
///     // DevTools will show setup instructions if JSON is not available
///   }
///
///   runApp(
///     ProviderScope(
///       observers: [RiverpodDevToolsObserver()],
///       child: MyApp(),
///     ),
///   );
/// }
/// ```
final class RiverpodDevToolsObserver extends ProviderObserver {
  RiverpodDevToolsObserver({int maxBufferSize = 1000})
      : _httpServer = RiverpodDevToolsHttpServer(maxBufferSize: maxBufferSize) {
    if (kDebugMode) {
      unawaited(_httpServer.start());
    }
  }

  final RiverpodDevToolsHttpServer _httpServer;

  /// Whether any consumer can observe events right now.
  ///
  /// In debug mode the local HTTP buffer (MCP) always needs events. Outside
  /// debug mode, events only matter when a DevTools client is listening on
  /// the Extension stream — otherwise `developer.postEvent` drops them, so
  /// serializing values would be pure overhead on every provider change.
  bool get _hasConsumer =>
      kDebugMode || developer.extensionStreamHasListener;

  @override
  void didAddProvider(
    covariant Object context,
    Object? value, [
    covariant Object? arg3, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    if (!_hasConsumer) return;
    final provider = _getProvider(context);
    final providerName = _getProviderName(provider);

    _postEvent('provider_added', {
      ..._buildProviderEventData(provider, providerName),
      'value': serializeValue(value),
    });
  }

  @override
  void didUpdateProvider(
    covariant Object context,
    Object? previousValue,
    Object? newValue, [
    covariant Object? arg4, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    if (!_hasConsumer) return;
    final provider = _getProvider(context);
    final providerName = _getProviderName(provider);

    _postEvent('provider_updated', {
      ..._buildProviderEventData(provider, providerName),
      'previousValue': serializeValue(previousValue),
      'newValue': serializeValue(newValue),
    });
  }

  @override
  void didDisposeProvider(
    covariant Object context, [
    covariant Object? arg2, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    if (!_hasConsumer) return;
    final provider = _getProvider(context);
    final providerName = _getProviderName(provider);

    _postEvent('provider_disposed', {
      ..._buildProviderEventData(provider, providerName),
    });
  }

  /// Caches the API probe result: true once `context.provider` has succeeded
  /// (Riverpod 3.0), false once it has thrown (Riverpod 2.x). The Riverpod
  /// version cannot change at runtime, so probing (and throwing/catching
  /// NoSuchMethodError) on every single event is wasted work.
  bool? _contextHasProviderProperty;

  /// Extracts the provider from either ProviderObserverContext (3.0) or ProviderBase (2.x)
  dynamic _getProvider(Object arg) {
    // In Riverpod 3.0, arg is ProviderObserverContext which has a 'provider' property.
    // In Riverpod 2.x, arg is directly ProviderBase.
    if (_contextHasProviderProperty == false) return arg;
    try {
      final dynamic context = arg;
      // ignore: avoid_dynamic_calls
      final provider = context.provider;
      _contextHasProviderProperty = true;
      return provider;
    } on NoSuchMethodError {
      // If 'provider' property doesn't exist, it's likely the 2.x API where arg is the provider itself.
      _contextHasProviderProperty = false;
      return arg;
    } catch (_) {
      // Fallback for other errors
      return arg;
    }
  }

  /// Gets the provider name safely
  String _getProviderName(dynamic provider) {
    if (provider == null) return 'Unknown';

    try {
      // ignore: avoid_dynamic_calls
      final name = provider.name;
      if (name != null) return name.toString();
    } catch (_) {
      // Field might not exist on some provider types
    }

    return provider.runtimeType.toString();
  }

  /// Get dependencies from static analysis only
  List<String> _getDependencies(String providerName) {
    return RiverpodDevToolsRegistry.instance.getDependencyNames(providerName);
  }

  /// Track which source provided the data
  /// Returns:
  /// - 'static' if metadata exists for this provider
  /// - 'name_mismatch' if JSON was loaded but this provider name doesn't match
  /// - 'none' if no JSON data was loaded at all
  String _getDependencySource(String providerName) {
    final hasStatic =
        RiverpodDevToolsRegistry.instance.hasMetadata(providerName);
    if (hasStatic) return 'static';

    final hasAnyData = RiverpodDevToolsRegistry.instance.hasAnyData;
    return hasAnyData ? 'name_mismatch' : 'none';
  }

  Map<String, Object?> _buildProviderEventData(
      dynamic provider, String providerName) {
    return {
      'providerId': identityHashCode(provider).toString(),
      'provider': providerName,
      'dependencies': _getDependencies(providerName),
      'dependenciesSource': _getDependencySource(providerName),
      'dependenciesLoadedAt': RiverpodDevToolsRegistry
          .instance.lastLoadedTimestamp?.millisecondsSinceEpoch,
      'dependenciesGeneratedAt': RiverpodDevToolsRegistry
          .instance.jsonGeneratedTimestamp?.millisecondsSinceEpoch,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }

  void _postEvent(String kind, Map<String, Object?> data) {
    developer.postEvent('riverpod:$kind', data);
    if (kDebugMode) {
      _httpServer.addEvent({'type': kind, ...data});
    }
  }
}
