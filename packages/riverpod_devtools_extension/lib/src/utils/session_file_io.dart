import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Browser file download/upload for session import/export. The extension
/// only ever runs on web (inside DevTools), so these use the DOM directly.
/// Kept apart from [session_io.dart] so the serialization logic stays
/// pure and unit-testable.

/// Triggers a browser download of [content] as [filename] via a transient
/// object-URL anchor.
void downloadTextFile(String filename, String content) {
  final bytes = Uint8List.fromList(utf8.encode(content));
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

/// Opens the browser file picker and returns the chosen file's text, or
/// null if the user cancels. Only `.json`/text files are offered.
Future<String?> pickTextFile() {
  final completer = Completer<String?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = '.json,application/json'
    ..style.display = 'none';
  web.document.body?.appendChild(input);

  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      input.remove();
      completer.complete(null);
      return;
    }
    final reader = web.FileReader();
    reader.onload = (web.Event _) {
      input.remove();
      final result = reader.result;
      completer.complete((result as JSString?)?.toDart);
    }.toJS;
    reader.onerror = (web.Event _) {
      input.remove();
      completer.complete(null);
    }.toJS;
    reader.readAsText(files.item(0)!);
  }.toJS;

  // If the picker is dismissed without a selection, no `change` fires; the
  // input just lingers hidden. That is harmless (it is replaced next time),
  // so we simply never complete in that case — the caller's await resolves
  // only on an actual pick.
  input.click();
  return completer.future;
}
