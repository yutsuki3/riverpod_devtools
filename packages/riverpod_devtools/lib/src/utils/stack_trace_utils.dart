/// Formats a stack trace for event payloads: drops Riverpod-internal
/// frames (they are the same for every failure and bury the user's code)
/// and caps the result at [maxFrames] lines.
///
/// If filtering would remove everything (a failure entirely inside
/// Riverpod internals), the unfiltered head of the trace is returned
/// instead so the payload is never empty.
String formatStackTrace(StackTrace stackTrace, {int maxFrames = 20}) {
  final lines = stackTrace
      .toString()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();

  final filtered = <String>[];
  for (final line in lines) {
    if (line.contains('package:riverpod') ||
        line.contains('package:flutter_riverpod')) {
      continue;
    }
    filtered.add(line);
    if (filtered.length >= maxFrames) break;
  }

  if (filtered.isNotEmpty) return filtered.join('\n');
  return lines.take(maxFrames).join('\n');
}

/// Caps [message] at [maxLength] characters so a huge error `toString()`
/// (e.g. an HTTP error carrying a response body) cannot bloat the event
/// buffer.
String truncateErrorMessage(String message, {int maxLength = 2000}) {
  if (message.length <= maxLength) return message;
  return '${message.substring(0, maxLength)}… (truncated)';
}
