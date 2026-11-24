import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Hands a generated file to the browser. It opens in a separate tab: on a
/// phone (above all the installed app on iPhone) a PDF would otherwise
/// replace the app's page, and coming back would reload the app and lose
/// the work in progress. Desktop browsers still just download it.
void downloadBytes(List<int> bytes, String filename, String mimeType) {
  final blob = web.Blob(
    <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..target = '_blank'
    ..rel = 'noopener';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // The new tab reads the file after this returns: free it only later.
  Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
}
