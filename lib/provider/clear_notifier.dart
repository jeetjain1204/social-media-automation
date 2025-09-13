import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Notifier that allows a one-shot "clear" signal.
/// Usage pattern:
///   if (context.watch<ClearNotifier>().shouldClear) { ... do clear ...; context.read<ClearNotifier>().acknowledgeClear(); }
///
/// Behavior notes (kept as-is):
/// - `triggerClear()` sets the flag to true and *always* notifies listeners, even if it was already true.
///   This allows re-triggering a clear event without requiring an acknowledge in between.
/// - `acknowledgeClear()` resets the flag to false and does *not* notify. Consumers typically clear
///   UI state during the same build cycle they observed the flag, then call acknowledge.
class ClearNotifier extends ChangeNotifier {
  bool _shouldClear = false;

  /// Current clear signal state.
  bool get shouldClear => _shouldClear;

  /// Set the clear signal and notify listeners.
  /// Keeps the original semantics: even if already true, we still notify to allow re-triggers.
  void triggerClear() {
    // OPT: Keep re-trigger semantics to avoid behavior change; explicit comment for maintainers.
    _shouldClear = true;
    notifyListeners();
  }

  /// Acknowledge/consume the clear signal without notifying.
  /// Consumers usually call this right after reacting to `shouldClear`.
  void acknowledgeClear() {
    // OPT: No notify here by design to avoid redundant rebuilds in listeners that already reacted.
    _shouldClear = false;
  }

  /// OPT (DX helper): Atomically consume the flag and return whether it was set.
  /// This avoids a racey read-then-clear in callers and reduces boilerplate.
  /// Does not change existing API behavior; simply a convenience.
  @pragma('vm:prefer-inline')
  bool consumeClear() {
    if (_shouldClear) {
      _shouldClear = false;
      // No notify, preserving acknowledge semantics.
      return true;
    }
    return false;
  }
}
