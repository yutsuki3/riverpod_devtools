import 'dart:async' show unawaited;
import 'dart:convert' show jsonEncode;
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'http_server_support.dart';
import 'static_dependencies.dart';
import 'trigger_tracker.dart';
import 'utils/serialization.dart';
import 'utils/stack_trace_utils.dart';

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
      _httpServer.commandHandler = executeCommand;
      _commandTarget = this;
      _registerCommandExtension();
    }
  }

  /// Service extension DevTools calls to run state commands
  /// (invalidate/refresh) inside the app.
  static const commandExtensionName = 'ext.riverpod_devtools.command';

  /// registerExtension is per-isolate and permanent, so the extension is
  /// registered once and routed to the most recently constructed observer
  /// (a new observer replaces the old one on hot restart).
  static bool _commandExtensionRegistered = false;
  static RiverpodDevToolsObserver? _commandTarget;

  static void _registerCommandExtension() {
    if (_commandExtensionRegistered) return;
    _commandExtensionRegistered = true;
    try {
      developer.registerExtension(commandExtensionName,
          (method, parameters) async {
        final result = _commandTarget?.executeCommand(
              parameters['action'] ?? '',
              parameters['provider'] ?? '',
            ) ??
            {'status': 'error', 'message': 'No active observer.'};
        return developer.ServiceExtensionResponse.result(jsonEncode(result));
      });
    } catch (error) {
      developer.log(
        'riverpod_devtools: failed to register $commandExtensionName; '
        'invalidate/refresh from DevTools will not work.',
        name: 'riverpod_devtools',
        error: error,
      );
    }
  }

  /// Live provider instances (with the container that owns them) by name,
  /// so state commands can target them. Filled in [didAddProvider],
  /// cleared in [didDisposeProvider].
  final Map<String, ({Object container, Object provider})> _aliveProviders =
      {};

  /// Executes a state command coming from DevTools (service extension) or
  /// MCP (`POST /commands`). Supported actions: `invalidate` (mark the
  /// provider for rebuild) and `refresh` (invalidate, then re-read
  /// immediately so it rebuilds even without listeners). Returns a
  /// JSON-encodable result map with `status: ok | error`.
  @visibleForTesting
  Map<String, Object?> executeCommand(String action, String providerName) {
    if (action != 'invalidate' && action != 'refresh') {
      return {
        'status': 'error',
        'message':
            'Unknown action "$action". Supported: invalidate, refresh.',
      };
    }
    final target = _aliveProviders[providerName];
    if (target == null) {
      return {
        'status': 'error',
        'message': 'Provider "$providerName" is not alive '
            '(unknown name or already disposed).',
      };
    }
    try {
      final dynamic container = target.container;
      final dynamic provider = target.provider;
      // ignore: avoid_dynamic_calls
      container.invalidate(provider);
      if (action == 'refresh') {
        // ignore: avoid_dynamic_calls
        container.read(provider);
      }
      return {'status': 'ok', 'action': action, 'provider': providerName};
    } catch (error) {
      return {
        'status': 'error',
        'message': 'Failed to $action "$providerName": $error',
      };
    }
  }

  final RiverpodDevToolsHttpServer _httpServer;

  /// Monotonic per-observer event sequence. Timestamps have millisecond
  /// resolution and collide within a burst of updates, so consumers use
  /// [seq] for unambiguous ordering and for `triggeredBy` references.
  int _eventSeq = 0;

  final UpdateTriggerTracker _triggerTracker = UpdateTriggerTracker();

  /// The events buffered for the local MCP endpoint, exposed so tests can
  /// assert on posted payloads (developer.postEvent is not interceptable).
  @visibleForTesting
  List<Map<String, Object?>> get bufferedEventsForTesting =>
      _httpServer.eventsFor();

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
    final id = _identify(provider);

    final container = _getContainer(context, arg3);
    if (container != null && provider != null) {
      _aliveProviders[id.displayName] =
          (container: container, provider: provider as Object);
    }

    _postEvent('provider_added', {
      ..._buildProviderEventData(provider, id),
      // Full dependency info (kind + source location) is only attached to
      // the rare added events; updates carry just the names.
      'dependencyDetails': RiverpodDevToolsRegistry.instance
          .getDependenciesWithDetails(id.base),
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
    final id = _identify(provider);

    final data = _buildProviderEventData(provider, id);
    final seq = data['seq'] as int;
    final nowMs = data['timestamp'] as int;
    final triggers = _triggerTracker.triggersFor(
      id.displayName,
      data['dependencies'] as List<String>,
      nowMs,
    );
    if (triggers.isNotEmpty) {
      data['triggeredBy'] = triggers;
      data['triggerConfidence'] = 'inferred';
    }
    _triggerTracker.recordUpdate(id.displayName, seq, nowMs);

    _postEvent('provider_updated', {
      ...data,
      'previousValue': serializeValue(previousValue),
      'newValue': serializeValue(newValue),
    });
  }

  @override
  void providerDidFail(
    covariant Object context,
    Object error,
    StackTrace stackTrace, [
    covariant Object? arg4, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    if (!_hasConsumer) return;
    final provider = _getProvider(context);
    final id = _identify(provider);

    _postEvent('provider_failed', {
      ..._buildProviderEventData(provider, id),
      'error': {
        'type': error.runtimeType.toString(),
        'message': truncateErrorMessage(error.toString()),
        'stackTrace': formatStackTrace(stackTrace),
      },
    });
  }

  @override
  void didDisposeProvider(
    covariant Object context, [
    covariant Object? arg2, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    if (!_hasConsumer) return;
    final provider = _getProvider(context);
    final id = _identify(provider);

    _aliveProviders.remove(id.displayName);

    _postEvent('provider_disposed', {
      ..._buildProviderEventData(provider, id),
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

  /// Extracts the owning ProviderContainer: `context.container` on
  /// Riverpod 3.0, the trailing container argument on 2.x.
  Object? _getContainer(Object arg, Object? legacyContainer) {
    if (_contextHasProviderProperty != false) {
      try {
        final dynamic context = arg;
        // ignore: avoid_dynamic_calls
        final container = context.container;
        if (container != null) return container as Object;
      } catch (_) {
        // Not a 3.0 ProviderObserverContext; fall through to the 2.x arg.
      }
    }
    return legacyContainer;
  }

  /// Gets the provider's base name safely (the family name for family
  /// instances — shared across a family's instances).
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

  /// Identifies a provider for the DevTools UI, distinguishing family
  /// instances (which share a base [name] but differ by [argument]) so they
  /// no longer collapse into a single entry.
  ///
  /// - [displayName]: unique per instance (`family(argument)` for family
  ///   instances, the base name otherwise) — used as the event/UI identity.
  /// - [base]: the base name — used for static-dependency lookups, which are
  ///   keyed on the provider *definition*, not the instance.
  /// - [family] / [argument]: set only for family instances, letting the UI
  ///   group instances under their family.
  ({String displayName, String base, String? family, String? argument})
      _identify(dynamic provider) {
    final base = _getProviderName(provider);
    try {
      // A non-null `from` marks a `.family` instance on both Riverpod 2.x
      // and 3.x.
      // ignore: avoid_dynamic_calls
      final from = provider.from;
      if (from != null) {
        // ignore: avoid_dynamic_calls
        final argument = provider.argument?.toString() ?? '';
        return (
          displayName: '$base($argument)',
          base: base,
          family: base,
          argument: argument,
        );
      }
    } catch (_) {
      // Not a family (or the API differs); fall through to the plain name.
    }
    return (displayName: base, base: base, family: null, argument: null);
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
    dynamic provider,
    ({String displayName, String base, String? family, String? argument}) id,
  ) {
    return {
      'seq': ++_eventSeq,
      'providerId': identityHashCode(provider).toString(),
      'provider': id.displayName,
      if (id.family != null) 'family': id.family,
      if (id.argument != null) 'argument': id.argument,
      // Dependencies are per definition, so look them up by base name.
      'dependencies': _getDependencies(id.base),
      'dependenciesSource': _getDependencySource(id.base),
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
