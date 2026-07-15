/// Coerces a value that should be an integer but may arrive in a client-quirk
/// form: an `int`, a whole-numbered `double` (some MCP/HTTP clients encode
/// integers as doubles, e.g. `50.0`), or the string form of either
/// (`"50"`, `"50.0"` in query parameters).
///
/// Returns null when the value is absent or not numeric. This is the single
/// definition of that leniency — the MCP server (JSON arguments) and the
/// in-app HTTP server (query strings) both route through it so the two layers
/// can't drift apart.
int? coerceInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? num.tryParse(value)?.toInt();
  }
  return null;
}
