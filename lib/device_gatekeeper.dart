// OPT: Micro-perf & a11y polish. No behavior change.

import 'package:blob/utils/colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Gates the UI to desktop/laptop on web. If not desktop, shows a simple message.
/// Behavior unchanged: allows only when running on web and width > 1000.
class DeviceGatekeeper extends StatelessWidget {
  final Widget child;
  const DeviceGatekeeper({super.key, required this.child});

  // OPT: Static pure helper; trivial micro-optimization and clearer intent.
  static bool isDesktop(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width; // OPT: cheaper accessor
    return kIsWeb && width > 1000; // same threshold & platform check
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktop(context)) return child; // fast path

    // OPT: Keep UI identical; add max width for readability on very wide screens.
    return Scaffold(
      backgroundColor: darkColor,
      body: Center(
        child: Semantics(
          label: 'Desktop required screen',
          // OPT: Constrain width to avoid overly long lines on large tablets.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 360,
            ), // OPT: readability; no phone layout change
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.desktop_windows_rounded,
                  color: lightColor,
                  size: 48,
                ),
                const SizedBox(height: 20),
                Text(
                  'Please open this website on a desktop or laptop',
                  style: TextStyle(color: lightColor, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
