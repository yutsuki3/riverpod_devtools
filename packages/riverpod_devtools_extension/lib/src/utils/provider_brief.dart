import 'dart:convert';

import '../models/event_type.dart';
import '../models/provider_event.dart';
import '../models/provider_info.dart';

/// Longest value text (JSON) included in a brief; longer values are cut and
/// flagged so a pasted brief stays small enough for an AI chat.
const _maxValueChars = 1500;

/// Markdown snapshot of one provider, meant to be pasted into an AI chat:
/// status, current value, error, static dependencies, and the latest events.
///
/// Pure (no widgets, no clock) so it is cheap to unit test. [events] must be
/// newest first, as the inspector stores them; at most [maxEvents] are shown.
String buildProviderBrief(
  ProviderInfo provider, {
  required List<String> usedBy,
  required List<ProviderEvent> events,
  int maxEvents = 5,
}) {
  final out = StringBuffer()
    ..writeln('## Riverpod provider: ${provider.name}')
    ..writeln()
    ..writeln('- Status: ${provider.status.name}');
  if (provider.family != null) {
    out.writeln('- Family: ${provider.family} (argument: '
        '${provider.argument ?? 'unknown'})');
  }

  final (valueText, lossy) = _valueText(provider.value);
  out
    ..writeln()
    ..writeln('### Current value${lossy ? ' (truncated)' : ''}')
    ..writeln('```json')
    ..writeln(valueText)
    ..writeln('```');

  final error = provider.lastError;
  if (error != null) {
    out
      ..writeln()
      ..writeln('### Error')
      ..writeln('- Type: ${error['type']}')
      ..writeln('- Message: ${error['message']}');
    final stack = error['stackTrace']?.toString();
    if (stack != null && stack.isNotEmpty) {
      out
        ..writeln('```')
        ..writeln(stack.split('\n').take(10).join('\n'))
        ..writeln('```');
    }
  }

  out
    ..writeln()
    ..writeln('### Dependencies');
  switch (provider.dependenciesSource) {
    case DependencySource.static:
      out
        ..writeln('- Depends on: ${_list(_dependsOn(provider))}')
        ..writeln('- Used by: ${_list(usedBy)}');
    case DependencySource.loadError:
      out.writeln('- Unavailable: riverpod_dependencies.json failed to load '
          '(${provider.dependenciesLoadError ?? 'unknown error'}); regenerate '
          'it with `dart run riverpod_devtools:analyze` and hot-restart.');
    case DependencySource.nameMismatch:
      out.writeln('- Unavailable: no static data matches this provider name '
          '(re-run `dart run riverpod_devtools:analyze`).');
    case DependencySource.none:
      out.writeln('- Unavailable: no static dependency data loaded '
          '(run `dart run riverpod_devtools:analyze`).');
  }

  out
    ..writeln()
    ..writeln('### Recent events (newest first)');
  if (events.isEmpty) {
    out.writeln('- none recorded');
  }
  for (final event in events.take(maxEvents)) {
    out.writeln(_eventLine(event));
  }
  return out.toString().trimRight();
}

String _list(List<String> names) => names.isEmpty ? 'none' : names.join(', ');

/// `name (watch)` when the analyzer recorded how it is consumed.
List<String> _dependsOn(ProviderInfo provider) {
  final kinds = {
    for (final detail in provider.dependencyDetails)
      if (detail.type != null) detail.providerName: detail.type!,
  };
  return [
    for (final name in provider.dependencies)
      kinds.containsKey(name) ? '$name (${kinds[name]})' : name,
  ];
}

String _eventLine(ProviderEvent event) {
  final t = event.timestamp;
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  final seq = event.seq == null ? '' : '#${event.seq} ';
  final buffer = StringBuffer('- $seq$time ${event.type.name}');
  switch (event.type) {
    case EventType.updated:
      buffer
          .write(': ${_short(event.previousValue)} -> ${_short(event.value)}');
    case EventType.added:
      buffer.write(': ${_short(event.value)}');
    case EventType.failed:
      buffer.write(': ${event.error?['type']}: ${event.error?['message']}');
    case EventType.disposed:
      break;
  }
  if (event.triggeredBy.isNotEmpty) {
    buffer.write(
        ' (triggered by ${event.triggeredBy.map((r) => r.provider).join(', ')})');
  }
  return buffer.toString();
}

String _short(Map<String, dynamic>? value) {
  if (value == null) return 'null';
  final text = jsonEncode(_unwrap(value));
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

(String, bool) _valueText(Map<String, dynamic> value) {
  final unwrapped = _unwrap(value);
  final text = const JsonEncoder.withIndent('  ').convert(unwrapped);
  final tooLong = text.length > _maxValueChars;
  final lossy = tooLong || _isLossy(value);
  return (tooLong ? '${text.substring(0, _maxValueChars)}…' : text, lossy);
}

bool _isLossy(Object? node) {
  if (node is Map) {
    return node['lossy'] == true || node.values.any(_isLossy);
  }
  if (node is List) return node.any(_isLossy);
  return false;
}

/// Strips the serializer's `{type, string, items, entries, value}` wrappers
/// down to plain JSON: scalars stay as-is, collections become lists / maps.
Object? _unwrap(Object? node) {
  if (node is List) return node.map(_unwrap).toList();
  if (node is! Map) return node;
  if (node.containsKey('entries')) {
    return {
      for (final entry in (node['entries'] as List).whereType<Map>())
        '${entry['key']}': _unwrap(entry['value']),
    };
  }
  if (node.containsKey('items')) return _unwrap(node['items']);
  if (node.containsKey('value')) return _unwrap(node['value']);
  if (node.containsKey('string')) return node['string'];
  return node.map((k, v) => MapEntry('$k', _unwrap(v)));
}
