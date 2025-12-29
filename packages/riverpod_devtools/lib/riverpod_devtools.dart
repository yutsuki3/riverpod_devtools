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
      'provider': provider.name ?? provider.runtimeType.toString(),
      'value': _serializeValue(value),
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
      'provider': provider.name ?? provider.runtimeType.toString(),
      'previousValue': _serializeValue(previousValue),
      'newValue': _serializeValue(newValue),
    });
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    _postEvent('provider_disposed', {
      'provider': provider.name ?? provider.runtimeType.toString(),
    });
  }

  void _postEvent(String kind, Map<String, Object?> data) {
    developer.postEvent('riverpod:$kind', data);
  }

  String _serializeValue(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }
}
