import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/bluetooth/signal_strength.dart';

void main() {
  test('maps RSSI to signal levels at the boundaries', () {
    expect(SignalLevel.fromRssi(-30), SignalLevel.good);
    expect(SignalLevel.fromRssi(-67), SignalLevel.good);
    expect(SignalLevel.fromRssi(-68), SignalLevel.medium);
    expect(SignalLevel.fromRssi(-80), SignalLevel.medium);
    expect(SignalLevel.fromRssi(-81), SignalLevel.weak);
    expect(SignalLevel.fromRssi(-110), SignalLevel.weak);
  });

  test('more signal fills more bars', () {
    expect(SignalLevel.weak.bars, 1);
    expect(SignalLevel.medium.bars, 2);
    expect(SignalLevel.good.bars, 3);
  });
}
