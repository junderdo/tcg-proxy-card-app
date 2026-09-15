enum SignalLevel {
  weak(bars: 1, label: 'weak'),
  medium(bars: 2, label: 'medium'),
  good(bars: 3, label: 'good');

  const SignalLevel({required this.bars, required this.label});

  final int bars;
  final String label;

  static const maxBars = 3;
  static const goodMinRssi = -67;
  static const mediumMinRssi = -80;

  static SignalLevel fromRssi(int rssi) {
    if (rssi >= goodMinRssi) return good;
    if (rssi >= mediumMinRssi) return medium;
    return weak;
  }
}
