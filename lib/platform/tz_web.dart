import 'package:js/js_util.dart' as jsu;

Future<String?> browserTimeZone() async {
  final intl = jsu.getProperty(jsu.globalThis, 'Intl');
  final dtf = jsu.callMethod(intl, 'DateTimeFormat', const []);
  final opts = jsu.callMethod(dtf, 'resolvedOptions', const []);
  final tz = jsu.getProperty(opts, 'timeZone');
  return tz is String ? tz : null;
}
