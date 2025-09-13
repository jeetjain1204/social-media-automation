import 'dart:typed_data';
import 'package:universal_html/html.dart' as html;
import 'package:js/js_util.dart' as jsu;

Future<void> downloadBytes(String name, Uint8List bytes) async {
  final blob = html.Blob([bytes], 'application/octet-stream');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = name
    ..click();
  html.Url.revokeObjectUrl(url);
}

Future<void> injectScriptOnce(String id, String src) async {
  var s = html.document.querySelector('#$id') as html.ScriptElement?;
  if (s == null) {
    s = html.ScriptElement()
      ..id = id
      ..src = src
      ..defer = true;
    html.document.body!.append(s);
    await s.onLoad.first;
  }
}

void setBeforeUnloadGuard(bool enable) {
  if (!enable) return;
  html.window.onBeforeUnload.listen((e) {
    (e as html.BeforeUnloadEvent).returnValue = '';
  });
}

Future<String?> getLocalTimezone() async {
  final intl = jsu.getProperty(jsu.globalThis, 'Intl');
  final dtf = jsu.callMethod(intl, 'DateTimeFormat', const []);
  final opts = jsu.callMethod(dtf, 'resolvedOptions', const []);
  return jsu.getProperty(opts, 'timeZone') as String?;
}
