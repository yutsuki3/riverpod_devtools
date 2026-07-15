import 'dart:async' show unawaited;
import 'dart:collection' show HashMap;
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
/// In debug mode on native platforms, it also starts a local HTTP server
/// (the first free port in 8788–8797) so that MCP tools can read the event log.
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
///   } catch (e) {
///     // The asset is missing or unreadable. Log the reason instead of
///     // swallowing it silently — DevTools/MCP will otherwise just show an
///     // empty dependency graph with no hint as to why.
///     debugPrint('riverpod_devtools: could not load dependency data: $e');
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
      // Only mark as registered once registration actually succeeds, so a
      // failure can be retried by the next observer instead of being latched
      // off for the rest of the isolate's life.
      _commandExtensionRegistered = true;
    } catch (error) {
      developer.log(
        'riverpod_devtools: failed to register $commandExtensionName; '
        'invalidate/refresh from DevTools will not work.',
        name: 'riverpod_devtools',
        error: error,
      );
    }
  }

  /// Command targets: the provider *definition* (and its owning container)
  /// keyed by a stable, session-unique [instanceId] — NOT by display name,
  /// which can collide (two unnamed `Provider<int>`s, or two providers that
  /// share a `name:`). Keying by name silently overwrote one with the
  /// other, so a command could hit the wrong provider; keying by instanceId
  /// keeps every distinct provider addressable.
  ///
  /// A provider definition is stable and can be invalidated / read at any
  /// time, so — unlike a snapshot of "what is live right now" — this is kept
  /// across dispose. That is what makes a second invalidate/refresh work:
  /// invalidate itself disposes the provider, and its rebuild is not always
  /// reported back before the next command, so a liveness snapshot would
  /// spuriously report the still-in-use provider as gone. Bounded by
  /// [_maxCommandTargets] with FIFO eviction so long-lived apps with high
  /// family-instance churn don't grow this without limit.
  final Map<String, ({Object container, Object provider, String name})>
      _commandTargets = {};

  /// Assigns a stable [instanceId] to each distinct provider *object*,
  /// reusing it whenever the same object is seen again (identity keys, so
  /// two `==`-equal-but-distinct providers still get separate ids). This is
  /// what makes unnamed / same-named providers individually addressable.
  final Map<Object, String> _instanceIdByProvider =
      HashMap<Object, String>(equals: identical, hashCode: identityHashCode);

  /// Display name → the instanceIds currently sharing it. A name with more
  /// than one live id is ambiguous: a command that targets it by name is
  /// rejected in favor of the exact instanceId.
  final Map<String, Set<String>> _instanceIdsByName = {};

  int _instanceOrdinal = 0;

  static const int _maxCommandTargets = 2048;

  /// Returns the stable [instanceId] for [provider], assigning one (and
  /// registering it under [displayName]) the first time the object is seen.
  /// Null only when [provider] is null.
  String? _instanceIdFor(dynamic provider, String displayName) {
    if (provider == null) return null;
    final existing = _instanceIdByProvider[provider as Object];
    if (existing != null) return existing;
    final id = 'p${_instanceOrdinal++}';
    _instanceIdByProvider[provider] = id;
    _instanceIdsByName.putIfAbsent(displayName, () => <String>{}).add(id);
    return id;
  }

  /// Whether [displayName] currently maps to exactly one instance — i.e. the
  /// name alone unambiguously identifies a provider.
  bool _nameIsUnique(String displayName) =>
      (_instanceIdsByName[displayName]?.length ?? 0) <= 1;

  /// Remembers [provider] (and its owning container) as a command target,
  /// keyed by its stable [instanceId]. No-op when the container or provider
  /// can't be resolved.
  void _trackCommandTarget(
    Object context,
    dynamic provider,
    String instanceId,
    String displayName,
    Object? legacyArg,
  ) {
    final container = _getContainer(context, legacyArg);
    if (container == null || provider == null) return;
    // Refresh recency: re-insert so the most recently seen providers are
    // the last to be evicted.
    _commandTargets.remove(instanceId);
    _commandTargets[instanceId] = (
      container: container,
      provider: provider as Object,
      name: displayName,
    );
    if (_commandTargets.length > _maxCommandTargets) {
      _evictOldestCommandTarget();
    }
  }

  void _evictOldestCommandTarget() {
    final oldestId = _commandTargets.keys.first;
    final evicted = _commandTargets.remove(oldestId);
    if (evicted == null) return;
    // Keep the name index and instance-id map consistent with the eviction
    // so ambiguity/uniqueness stays accurate and memory stays bounded.
    final ids = _instanceIdsByName[evicted.name];
    if (ids != null) {
      ids.remove(oldestId);
      if (ids.isEmpty) _instanceIdsByName.remove(evicted.name);
    }
    _instanceIdByProvider.remove(evicted.provider);
  }

  /// Resolves a command [target] — either an exact instanceId or a provider
  /// display name — to a single command-target entry, or an error map when
  /// it is unknown or the name is ambiguous.
  ({String id, ({Object container, Object provider, String name}) entry})?
      _resolveTarget(String target, List<Map<String, Object?>> errorOut) {
    // Exact instanceId wins (unambiguous by construction).
    final direct = _commandTargets[target];
    if (direct != null) return (id: target, entry: direct);

    final ids = (_instanceIdsByName[target] ?? const <String>{})
        .where(_commandTargets.containsKey)
        .toList();
    if (ids.isEmpty) {
      errorOut.add({
        'status': 'error',
        'message': 'Provider "$target" is unknown '
            '(never observed by this app).',
      });
      return null;
    }
    if (ids.length > 1) {
      ids.sort();
      errorOut.add({
        'status': 'error',
        'message': 'Provider name "$target" is ambiguous — '
            '${ids.length} providers share it. Pass one of these instanceIds '
            'as "provider" instead: ${ids.join(', ')}.',
        'ambiguous': true,
        'candidates': ids,
      });
      return null;
    }
    return (id: ids.single, entry: _commandTargets[ids.single]!);
  }

  /// Executes a state command coming from DevTools (service extension) or
  /// MCP (`POST /commands`). Supported actions: `invalidate` (mark the
  /// provider for rebuild), `refresh` (invalidate, then re-read
  /// immediately so it rebuilds even without listeners), and `set` (write
  /// [value] into a writable notifier's state). [target] is either
  /// a provider display name or an exact instanceId. Returns a
  /// JSON-encodable result map with `status: ok | error`.
  @visibleForTesting
  Map<String, Object?> executeCommand(String action, String target,
      [Object? value]) {
    if (action != 'invalidate' && action != 'refresh' && action != 'set') {
      return {
        'status': 'error',
        'message':
            'Unknown action "$action". Supported: invalidate, refresh, set.',
      };
    }
    final errorOut = <Map<String, Object?>>[];
    final resolved = _resolveTarget(target, errorOut);
    if (resolved == null) return errorOut.first;
    final entry = resolved.entry;
    if (action == 'set') {
      return _executeSet(entry, resolved.id, value);
    }
    try {
      final dynamic container = entry.container;
      final dynamic provider = entry.provider;
      // ignore: avoid_dynamic_calls
      container.invalidate(provider);
      if (action == 'refresh') {
        // ignore: avoid_dynamic_calls
        container.read(provider);
      }
      return {
        'status': 'ok',
        'action': action,
        'provider': entry.name,
        'instanceId': resolved.id,
      };
    } catch (error) {
      return {
        'status': 'error',
        'message': 'Failed to $action "${entry.name}": $error',
      };
    }
  }

  /// Sets a provider's state to [value] (an already-decoded JSON scalar).
  /// v1 supports only providers with a writable notifier whose current state
  /// is a primitive; everything else is rejected with `supported: false`
  /// rather than guessed at. Reuses [_resolveTarget]'s result via [entry].
  Map<String, Object?> _executeSet(
    ({Object container, Object provider, String name}) entry,
    String instanceId,
    Object? value,
  ) {
    // Only primitives survive the JSON round-trip and can be assigned safely.
    if (!_isPrimitiveValue(value)) {
      return {
        'status': 'error',
        'supported': false,
        'message': 'set only supports primitive values (int, double, bool, '
            'String, null). Got ${value.runtimeType}.',
      };
    }

    final dynamic container = entry.container;
    final dynamic provider = entry.provider;

    dynamic notifier;
    try {
      // StateProvider / NotifierProvider expose a writable notifier here;
      // plain Provider / FutureProvider / StreamProvider have no `.notifier`
      // and throw, landing us in the catch below.
      // ignore: avoid_dynamic_calls
      notifier = container.read(provider.notifier);
    } catch (_) {
      return {
        'status': 'error',
        'supported': false,
        'message': 'Provider "${entry.name}" does not support set — only '
            'providers with a writable notifier (StateProvider, '
            'NotifierProvider) can be set. Use invalidate/refresh instead.',
      };
    }

    Object? current;
    try {
      // ignore: avoid_dynamic_calls
      current = notifier.state as Object?;
    } catch (_) {
      return {
        'status': 'error',
        'supported': false,
        'message': 'Provider "${entry.name}" has no readable state to set.',
      };
    }

    // A non-primitive *current* state excludes AsyncNotifier (state is an
    // AsyncValue) and any provider holding a custom object — neither can be
    // rebuilt from a JSON scalar.
    if (!_isPrimitiveValue(current)) {
      return {
        'status': 'error',
        'supported': false,
        'message': 'Provider "${entry.name}" holds a ${current.runtimeType} — '
            'v1 can only set providers whose state is a primitive (int, '
            'double, bool, String, null).',
      };
    }

    // JSON encodes e.g. `5` as an int even for a double-typed provider; widen
    // so the strongly-typed setter accepts it. Every other type mismatch is
    // left to the setter's own runtime check in the try below.
    var toSet = value;
    if (current is double && value is int) toSet = value.toDouble();

    try {
      // ignore: avoid_dynamic_calls
      notifier.state = toSet;
    } catch (error) {
      return {
        'status': 'error',
        'message': 'Failed to set "${entry.name}" to $toSet: $error. The '
            "provider's state type likely differs from the value's type.",
      };
    }

    return {
      'status': 'ok',
      'action': 'set',
      'provider': entry.name,
      'instanceId': instanceId,
      'value': toSet,
    };
  }

  static bool _isPrimitiveValue(Object? v) =>
      v == null || v is num || v is bool || v is String;

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
    final instanceId = _instanceIdFor(provider, id.displayName);

    if (instanceId != null) {
      _trackCommandTarget(context, provider, instanceId, id.displayName, arg3);
    }

    _postEvent('provider_added', {
      ..._buildProviderEventData(provider, id, instanceId),
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
    final instanceId = _instanceIdFor(provider, id.displayName);

    // Keep the command target's container reference fresh on updates too,
    // not just on the initial add.
    if (instanceId != null) {
      _trackCommandTarget(context, provider, instanceId, id.displayName, arg4);
    }

    final data = _buildProviderEventData(provider, id, instanceId);
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
    final instanceId = _instanceIdFor(provider, id.displayName);

    _postEvent('provider_failed', {
      ..._buildProviderEventData(provider, id, instanceId),
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
    final instanceId = _instanceIdFor(provider, id.displayName);

    // Intentionally NOT removing from _commandTargets: the definition stays
    // a valid invalidate/refresh target (invalidate disposes then rebuilds
    // the very provider being commanded). Disposed state is still conveyed
    // to the extension via the event below, which disables the buttons for
    // genuinely-disposed providers.

    _postEvent('provider_disposed', {
      ..._buildProviderEventData(provider, id, instanceId),
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
  /// - 'load_error' if the dependency JSON was found but failed to parse
  /// - 'name_mismatch' if JSON was loaded but this provider name doesn't match
  /// - 'none' if no JSON data was loaded at all
  String _getDependencySource(String providerName) {
    final registry = RiverpodDevToolsRegistry.instance;
    if (registry.hasMetadata(providerName)) return 'static';
    // A failed load is a distinct setup state: telling it apart from 'none'
    // lets the UI say "your JSON is broken" instead of "run the analyzer".
    if (registry.loadError != null) return 'load_error';
    return registry.hasAnyData ? 'name_mismatch' : 'none';
  }

  Map<String, Object?> _buildProviderEventData(
    dynamic provider,
    ({String displayName, String base, String? family, String? argument}) id,
    String? instanceId,
  ) {
    return {
      'seq': ++_eventSeq,
      'providerId': identityHashCode(provider).toString(),
      // Stable, session-unique handle. Unlike the display name it never
      // collides, so it is the reliable target for commands when a name is
      // shared by more than one provider.
      if (instanceId != null) 'instanceId': instanceId,
      'provider': id.displayName,
      // False when another provider currently shares this display name, so
      // consumers know to target by instanceId rather than by name.
      'nameIsUnique': _nameIsUnique(id.displayName),
      if (id.family != null) 'family': id.family,
      if (id.argument != null) 'argument': id.argument,
      // Dependencies are per definition, so look them up by base name.
      'dependencies': _getDependencies(id.base),
      'dependenciesSource': _getDependencySource(id.base),
      // Why loading failed, so the UI can show the actual reason. Only
      // attached while a load error is present.
      if (RiverpodDevToolsRegistry.instance.loadError case final String error)
        'dependenciesLoadError': error,
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
