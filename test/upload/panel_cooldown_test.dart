import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_proxy_card_app/upload/panel_cooldown.dart';

import '../support/upload_harness.dart';

void main() {
  late FakeClock clock;
  late InMemoryCooldownStore store;
  late PanelCooldown cooldown;

  setUp(() {
    clock = FakeClock();
    store = InMemoryCooldownStore();
    cooldown = PanelCooldown(store, clock: () => clock.now);
  });

  test('the cooldown is three minutes', () {
    expect(panelRefreshCooldown, const Duration(seconds: 180));
  });

  test('a device with no refresh has no cooldown', () {
    expect(cooldown.remainingFor('AA'), Duration.zero);
    expect(cooldown.isCoolingDown('AA'), isFalse);
  });

  test('counts down from a refresh, per device', () {
    cooldown.recordRefresh('AA');
    expect(cooldown.remainingFor('AA'), panelRefreshCooldown);
    expect(cooldown.remainingFor('BB'), Duration.zero);

    clock.advance(const Duration(seconds: 60));
    expect(cooldown.remainingFor('AA'), const Duration(seconds: 120));

    clock.advance(const Duration(seconds: 120));
    expect(cooldown.isCoolingDown('AA'), isFalse);
  });

  test("syncs to the device's remaining seconds", () {
    cooldown.recordRefresh('AA');
    cooldown.syncFromDevice('AA', const Duration(seconds: 42));
    expect(cooldown.remainingFor('AA'), const Duration(seconds: 42));

    cooldown.syncFromDevice('BB', const Duration(seconds: 170));
    expect(cooldown.remainingFor('BB'), const Duration(seconds: 170));
  });

  test('never waits longer than the cooldown if the clock goes back', () {
    cooldown.recordRefresh('AA');
    clock.advance(const Duration(hours: -2));
    expect(cooldown.remainingFor('AA'), panelRefreshCooldown);
  });

  test('notifies listeners when a cooldown starts', () {
    var notified = 0;
    cooldown.addListener(() => notified++);
    cooldown.recordRefresh('AA');
    expect(notified, 1);
  });

  test('saved cooldowns survive a restart', () async {
    await cooldown.recordRefresh('AA');
    clock.advance(const Duration(seconds: 30));

    final restarted = PanelCooldown(store, clock: () => clock.now);
    expect(restarted.remainingFor('AA'), Duration.zero);
    await restarted.load();

    expect(restarted.remainingFor('AA'), const Duration(seconds: 150));
  });

  test('persists through shared preferences', () async {
    SharedPreferences.setMockInitialValues({'unrelated': 1});
    final writer = PanelCooldown(
      const SharedPreferencesCooldownStore(),
      clock: () => clock.now,
    );
    await writer.syncFromDevice('AA:BB', const Duration(seconds: 100));

    final reader = PanelCooldown(
      const SharedPreferencesCooldownStore(),
      clock: () => clock.now,
    );
    await reader.load();

    expect(reader.remainingFor('AA:BB'), const Duration(seconds: 100));
  });

  test('formats countdowns as m:ss, rounding up', () {
    expect(formatCountdown(panelRefreshCooldown), '3:00');
    expect(formatCountdown(const Duration(milliseconds: 61200)), '1:02');
    expect(formatCountdown(const Duration(milliseconds: 400)), '0:01');
    expect(formatCountdown(Duration.zero), '0:00');
  });
}
