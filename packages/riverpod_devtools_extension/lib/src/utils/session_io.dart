import '../models/event_type.dart';
import '../models/provider_event.dart';
import '../models/provider_info.dart';

/// Bumped whenever the on-disk shape changes incompatibly. [decodeSession]
/// rejects versions it does not understand rather than silently mis-parsing.
const int kSessionFormatVersion = 1;

/// Thrown when [decodeSession] is handed JSON it cannot parse (wrong shape
/// or an unsupported [kSessionFormatVersion]). The message is safe to show
/// to the user.
class SessionDecodeException implements Exception {
  final String message;
  const SessionDecodeException(this.message);
  @override
  String toString() => message;
}

/// The providers + events reconstructed from an imported session file.
class DecodedSession {
  final Map<String, ProviderInfo> providers;

  /// Newest first, matching the live event list ordering.
  final List<ProviderEvent> events;

  const DecodedSession({required this.providers, required this.events});
}

/// Serializes the full inspector session — every provider (with its
/// dependency metadata and last error) plus the whole event log — to a
/// JSON-encodable map. The round-trip through [decodeSession] is lossless
/// for everything the UI renders, so an exported file re-imports to the
/// same view. Providers are written in insertion order and events newest
/// first, exactly as they are held in state.
Map<String, dynamic> encodeSession({
  required Map<String, ProviderInfo> providers,
  required List<ProviderEvent> events,
  DateTime? exportedAt,
}) {
  return {
    'formatVersion': kSessionFormatVersion,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'providers': [for (final p in providers.values) _encodeProvider(p)],
    'events': [for (final e in events) _encodeEvent(e)],
  };
}

/// Inverse of [encodeSession]. Throws [SessionDecodeException] on malformed
/// input.
DecodedSession decodeSession(Map<String, dynamic> json) {
  final version = json['formatVersion'];
  if (version is! int) {
    throw const SessionDecodeException(
        'Not a Riverpod DevTools session file (missing formatVersion).');
  }
  if (version > kSessionFormatVersion) {
    throw SessionDecodeException(
        'Session file version $version is newer than this DevTools '
        'extension supports (v$kSessionFormatVersion). Update the extension.');
  }

  final rawProviders = json['providers'];
  final rawEvents = json['events'];
  if (rawProviders is! List || rawEvents is! List) {
    throw const SessionDecodeException(
        'Session file is missing its providers or events list.');
  }

  final providers = <String, ProviderInfo>{};
  for (final raw in rawProviders) {
    if (raw is Map) {
      final info = _decodeProvider(raw.cast<String, dynamic>());
      providers[info.name] = info;
    }
  }

  final events = <ProviderEvent>[
    for (final raw in rawEvents)
      if (raw is Map) _decodeEvent(raw.cast<String, dynamic>()),
  ];

  return DecodedSession(providers: providers, events: events);
}

Map<String, dynamic> _encodeProvider(ProviderInfo p) {
  return {
    'id': p.id,
    'name': p.name,
    'value': p.value,
    'status': p.status.name,
    'dependencies': p.dependencies,
    'dependenciesSource': p.dependenciesSource.name,
    if (p.dependenciesLoadedAt != null)
      'dependenciesLoadedAt': p.dependenciesLoadedAt!.toIso8601String(),
    if (p.dependenciesGeneratedAt != null)
      'dependenciesGeneratedAt': p.dependenciesGeneratedAt!.toIso8601String(),
    if (p.lastError != null) 'lastError': p.lastError,
    if (p.dependencyDetails.isNotEmpty)
      'dependencyDetails': [
        for (final d in p.dependencyDetails)
          {
            'providerName': d.providerName,
            if (d.type != null) 'type': d.type,
            if (d.file != null) 'file': d.file,
            if (d.line != null) 'line': d.line,
          },
      ],
    if (p.family != null) 'family': p.family,
    if (p.argument != null) 'argument': p.argument,
  };
}

ProviderInfo _decodeProvider(Map<String, dynamic> json) {
  return ProviderInfo(
    id: json['id']?.toString() ?? 'unknown',
    name: json['name']?.toString() ?? 'Unknown',
    value: _asStringMap(json['value']) ?? const {'type': 'null', 'value': null},
    status: json['status'] == 'disposed'
        ? ProviderStatus.disposed
        : ProviderStatus.active,
    dependencies: _asStringList(json['dependencies']),
    dependenciesSource: _decodeSource(json['dependenciesSource']),
    dependenciesLoadedAt: _parseDate(json['dependenciesLoadedAt']),
    dependenciesGeneratedAt: _parseDate(json['dependenciesGeneratedAt']),
    lastError: _asStringMap(json['lastError']),
    dependencyDetails: [
      if (json['dependencyDetails'] is List)
        for (final d in json['dependencyDetails'] as List)
          if (d is Map && d['providerName'] != null)
            DependencyDetail(
              providerName: d['providerName'].toString(),
              type: d['type']?.toString(),
              file: d['file']?.toString(),
              line: d['line'] is int ? d['line'] as int : null,
            ),
    ],
    family: json['family']?.toString(),
    argument: json['argument']?.toString(),
  );
}

Map<String, dynamic> _encodeEvent(ProviderEvent e) {
  return {
    'type': e.type.name,
    'providerId': e.providerId,
    'providerName': e.providerName,
    if (e.previousValue != null) 'previousValue': e.previousValue,
    if (e.value != null) 'value': e.value,
    'timestamp': e.timestamp.toIso8601String(),
    if (e.seq != null) 'seq': e.seq,
    if (e.triggeredBy.isNotEmpty)
      'triggeredBy': [
        for (final t in e.triggeredBy)
          {'provider': t.provider, if (t.seq != null) 'seq': t.seq},
      ],
    if (e.error != null) 'error': e.error,
  };
}

ProviderEvent _decodeEvent(Map<String, dynamic> json) {
  return ProviderEvent(
    type: _decodeEventType(json['type']),
    providerId: json['providerId']?.toString() ?? 'unknown',
    providerName: json['providerName']?.toString() ?? 'Unknown',
    previousValue: _asStringMap(json['previousValue']),
    value: _asStringMap(json['value']),
    timestamp: _parseDate(json['timestamp']) ?? DateTime.now(),
    seq: json['seq'] is int ? json['seq'] as int : null,
    triggeredBy: [
      if (json['triggeredBy'] is List)
        for (final t in json['triggeredBy'] as List)
          if (t is Map && t['provider'] != null)
            TriggerRef(
              provider: t['provider'].toString(),
              seq: t['seq'] is int ? t['seq'] as int : null,
            ),
    ],
    error: _asStringMap(json['error']),
  );
}

EventType _decodeEventType(dynamic raw) {
  switch (raw) {
    case 'added':
      return EventType.added;
    case 'failed':
      return EventType.failed;
    case 'disposed':
      return EventType.disposed;
    case 'updated':
    default:
      return EventType.updated;
  }
}

DependencySource _decodeSource(dynamic raw) {
  switch (raw) {
    case 'static':
      return DependencySource.static;
    case 'nameMismatch':
      return DependencySource.nameMismatch;
    case 'none':
    default:
      return DependencySource.none;
  }
}

Map<String, dynamic>? _asStringMap(dynamic raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  return null;
}

List<String> _asStringList(dynamic raw) {
  if (raw is List) return [for (final e in raw) e.toString()];
  return const [];
}

DateTime? _parseDate(dynamic raw) {
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
