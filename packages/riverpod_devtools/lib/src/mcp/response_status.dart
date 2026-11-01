import 'dart:convert';

/// Whether an app response should be reported to the AI as a tool failure.
///
/// The in-app HTTP server signals failure two ways: a 4xx/5xx status (bad
/// query parameters, unknown path, internal error) and — for `POST /commands`
/// — a 200 whose JSON body carries `status: "error"` (unknown/ambiguous
/// provider, unsupported `set`, ...). Both must surface as `isError`, or an
/// AI reads a failed call as a success.
bool isFailedResponse(int statusCode, String body) {
  if (statusCode >= 400) return true;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map && decoded['status'] == 'error';
  } catch (_) {
    return false; // Not JSON (a plain-text body): nothing says it failed.
  }
}
