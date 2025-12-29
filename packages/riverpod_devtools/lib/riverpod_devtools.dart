library riverpod_devtools;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

class RiverpodDevToolsObserver extends ProviderObserver {
  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    _postEvent('provider_added', {
      'providerId': identityHashCode(provider).toString(),
      'provider': provider.name ?? provider.runtimeType.toString(),
      'value': _serializeValue(value),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    _postEvent('provider_updated', {
      'providerId': identityHashCode(provider).toString(),
      'provider': provider.name ?? provider.runtimeType.toString(),
      'previousValue': _serializeValue(previousValue),
      'newValue': _serializeValue(newValue),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    _postEvent('provider_disposed', {
      'providerId': identityHashCode(provider).toString(),
      'provider': provider.name ?? provider.runtimeType.toString(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
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
