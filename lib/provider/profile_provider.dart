import 'package:flutter/material.dart';

/// Notifier for broadcasting profile update events.
/// Usage: Call [notifyProfileUpdated] when the profile data changes
/// so any listening widgets can rebuild.
///
/// No state is stored in this notifier — it is purely a signal.
class ProfileNotifier extends ChangeNotifier {
  /// Notify all listeners that the profile has been updated.
  @pragma('vm:prefer-inline') // OPT: micro-perf for trivial call
  void notifyProfileUpdated() {
    notifyListeners();
  }
}
