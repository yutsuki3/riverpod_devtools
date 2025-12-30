library riverpod_devtools;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    _postEvent('provider_added', {
      'providerId': identityHashCode(provider).toString(),
      'provider': _getProviderName(provider),
      'value': _serializeValue(value),
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
    _postEvent('provider_updated', {
      'providerId': identityHashCode(provider).toString(),
      'provider': _getProviderName(provider),
      'previousValue': _serializeValue(previousValue),
      'newValue': _serializeValue(newValue),
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
    _postEvent('provider_disposed', {
      'providerId': identityHashCode(provider).toString(),
      'provider': _getProviderName(provider),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Extracts the provider from either ProviderObserverContext (3.0) or ProviderBase (2.x)
  dynamic _getProvider(Object arg) {
    // In Riverpod 3.0, arg is ProviderObserverContext which has a 'provider' property
    // In Riverpod 2.x, arg is directly ProviderBase
    try {
      // Try to access the 'provider' property (3.0 API)
      final dynamic context = arg;
      // ignore: avoid_dynamic_calls
      return context.provider;
    } catch (_) {
      // If that fails, it's the 2.x API where arg is already the provider
      return arg;
    }
  }

  /// Gets the provider name safely
  String _getProviderName(dynamic provider) {
    try {
      // ignore: avoid_dynamic_calls
      final name = provider.name;
      return name?.toString() ?? provider.runtimeType.toString();
    } catch (_) {
      return provider.runtimeType.toString();
    }
  }

  void _postEvent(String kind, Map<String, Object?> data) {
    developer.postEvent('riverpod:$kind', data);
  }

  String _serializeValue(Object? value) {
    try {
      if (value == null) return 'null';
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }
}
