import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The shortest time allowed between two refreshes of a card's panel.
/// Refreshing e-ink more often than this wears it out.
const panelRefreshCooldown = Duration(seconds: 180);

typedef Clock = DateTime Function();

/// Remembers, per device, when its panel may next be refreshed.
abstract interface class CooldownStore {
  Future<Map<String, DateTime>> readAll();
  Future<void> write(String deviceId, DateTime refreshAllowedAt);
}

class SharedPreferencesCooldownStore implements CooldownStore {
  const SharedPreferencesCooldownStore();

  static const _keyPrefix = 'panel_refresh_allowed_at.';

  @override
  Future<Map<String, DateTime>> readAll() async {
    final preferences = await SharedPreferences.getInstance();
    return {
      for (final key in preferences.getKeys())
        if (key.startsWith(_keyPrefix))
          if (preferences.getInt(key) case final millis?)
            key.substring(_keyPrefix.length):
                DateTime.fromMillisecondsSinceEpoch(millis),
    };
  }

  @override
  Future<void> write(String deviceId, DateTime refreshAllowedAt) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      '$_keyPrefix$deviceId',
      refreshAllowedAt.millisecondsSinceEpoch,
    );
  }
}

/// Tracks how long each card must rest before its panel can refresh again.
class PanelCooldown extends ChangeNotifier {
  PanelCooldown(this._store, {Clock? clock}) : _clock = clock ?? DateTime.now;

  final CooldownStore _store;
  final Clock _clock;
  final Map<String, DateTime> _refreshAllowedAt = {};
  Future<void>? _loading;
  bool _disposed = false;

  /// Loads saved cooldowns once; later calls wait for the same load.
  Future<void> load() => _loading ??= _load();

  Duration remainingFor(String deviceId) {
    final allowedAt = _refreshAllowedAt[deviceId];
    if (allowedAt == null) return Duration.zero;
    final remaining = allowedAt.difference(_clock());
    if (remaining <= Duration.zero) return Duration.zero;
    // A clock moved backwards shouldn't lock the device for longer than this.
    return remaining > panelRefreshCooldown ? panelRefreshCooldown : remaining;
  }

  bool isCoolingDown(String deviceId) => remainingFor(deviceId) > Duration.zero;

  /// Starts a full cooldown because the device's panel refreshed just now.
  Future<void> recordRefresh(String deviceId) =>
      _setAllowedAt(deviceId, _clock().add(panelRefreshCooldown));

  /// Adopts the device's own count, which includes refreshes the app didn't
  /// cause.
  Future<void> syncFromDevice(String deviceId, Duration remaining) =>
      _setAllowedAt(deviceId, _clock().add(remaining));

  Future<void> _load() async {
    final saved = await _store.readAll();
    saved.forEach(
      (id, allowedAt) => _refreshAllowedAt.putIfAbsent(id, () => allowedAt),
    );
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _setAllowedAt(String deviceId, DateTime allowedAt) async {
    _refreshAllowedAt[deviceId] = allowedAt;
    if (!_disposed) notifyListeners();
    await _store.write(deviceId, allowedAt);
  }
}

/// Formats a countdown as minutes and seconds, rounding up so it never shows
/// 0:00 while time remains.
String formatCountdown(Duration remaining) {
  final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
