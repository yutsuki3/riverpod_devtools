String formatRelativeTime(Duration duration) {
  if (duration.inSeconds < 60) {
    return '${duration.inSeconds}s ago';
  } else if (duration.inMinutes < 60) {
    return '${duration.inMinutes}m ago';
  } else if (duration.inHours < 24) {
    return '${duration.inHours}h ago';
  } else {
    return '${duration.inDays}d ago';
  }
}

String formatTimeDiff(Duration diff) {
  if (diff.inHours >= 1) {
    return '(+${diff.inHours}h)';
  } else if (diff.inMinutes >= 1) {
    return '(+${diff.inMinutes}m)';
  } else if (diff.inSeconds >= 1) {
    return '(+${diff.inSeconds}s)';
  } else if (diff.inMilliseconds > 0) {
    return '(+${diff.inMilliseconds}ms)';
  }
  return '';
}
