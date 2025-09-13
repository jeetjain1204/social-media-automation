import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

Future<void> downloadBytes(String name, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  // optional: Share or just leave saved.
}

Future<void> injectScriptOnce(String id, String src) async {}
void setBeforeUnloadGuard(bool enable) {}
Future<String?> getLocalTimezone() async => DateTime.now().timeZoneName;
Future<void> openExternal(String url) async =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
