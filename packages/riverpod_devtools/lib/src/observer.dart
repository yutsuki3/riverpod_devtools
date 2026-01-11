import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dependency_tracker.dart';
import 'utils/serialization.dart';

final _dependencyTracker = DependencyTracker();

/// A [ProviderObserver] that sends Riverpod events to the Flutter DevTools extension.
///
/// This observer monitors the lifecycle of all providers (add, update, dispose)
/// and posts events to the developer log, which the Riverpod DevTools extension listens to.
///
/// Usage:
/// ```dart
/// ProviderScope(
///   observers: [
///     RiverpodDevToolsObserver(),
///   ],
///   child: MyApp(),
/// );
/// ```
final class RiverpodDevToolsObserver extends ProviderObserver {
  @override
  void didAddProvider(
    covariant Object context,
    Object? value, [
    covariant Object? arg3, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    // Support both Riverpod 2.x and 3.0:
    // - Riverpod 3.0: didAddProvider(ProviderObserverContext context, Object? value)
    // - Riverpod 2.x: didAddProvider(ProviderBase provider, Object? value, ProviderContainer container)
    // The optional arg3 allows accepting both 2 and 3 parameters
    final provider = _getProvider(context);
    final providerId = identityHashCode(provider).toString();
    final providerName = _getProviderName(provider);

    // Record update (for dependency learning)
    _dependencyTracker.recordUpdate(providerId, providerName, isUpdate: false);

    // Get dependencies for this provider
    final dependencies = _dependencyTracker.getDependencies(providerId);

    _postEvent('provider_added', {
      'providerId': providerId,
      'provider': providerName,
      'value': serializeValue(value),
      'dependencies': dependencies,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void didUpdateProvider(
    covariant Object context,
    Object? previousValue,
    Object? newValue, [
    covariant Object? arg4, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    // Support both Riverpod 2.x and 3.0:
    // - Riverpod 3.0: didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue)
    // - Riverpod 2.x: didUpdateProvider(ProviderBase provider, Object? previousValue, Object? newValue, ProviderContainer container)
    // The optional arg4 allows accepting both 3 and 4 parameters
    final provider = _getProvider(context);
    final providerId = identityHashCode(provider).toString();
    final providerName = _getProviderName(provider);

    // Record update (for dependency learning)
    _dependencyTracker.recordUpdate(providerId, providerName, isUpdate: true);

    // Get dependencies for this provider
    final dependencies = _dependencyTracker.getDependencies(providerId);

    _postEvent('provider_updated', {
      'providerId': providerId,
      'provider': providerName,
      'previousValue': serializeValue(previousValue),
      'newValue': serializeValue(newValue),
      'dependencies': dependencies,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void didDisposeProvider(
    covariant Object context, [
    covariant Object? arg2, // Container in Riverpod 2.x, unused in 3.0
  ]) {
    // Support both Riverpod 2.x and 3.0:
    // - Riverpod 3.0: didDisposeProvider(ProviderObserverContext context)
    // - Riverpod 2.x: didDisposeProvider(ProviderBase provider, ProviderContainer container)
    // The optional arg2 allows accepting both 1 and 2 parameters
    final provider = _getProvider(context);
    final providerId = identityHashCode(provider).toString();

    // Clean up dependency tracking data to prevent memory leaks
    _dependencyTracker.removeProvider(providerId);

    _postEvent('provider_disposed', {
      'providerId': providerId,
      'provider': _getProviderName(provider),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Extracts the provider from either ProviderObserverContext (3.0) or ProviderBase (2.x)
  dynamic _getProvider(Object arg) {
    // In Riverpod 3.0, arg is ProviderObserverContext which has a 'provider' property.
    // In Riverpod 2.x, arg is directly ProviderBase.
    // We probe for the 'provider' property.
    try {
      final dynamic context = arg;
      // ignore: avoid_dynamic_calls
      return context.provider;
    } on NoSuchMethodError {
      // If 'provider' property doesn't exist, it's likely the 2.x API where arg is the provider itself.
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

  void _postEvent(String kind, Map<String, Object?> data) {
    developer.postEvent('riverpod:$kind', data);
  }
}
