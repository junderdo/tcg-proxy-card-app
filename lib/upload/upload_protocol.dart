import 'dart:typed_data';

import 'panel_frame.dart';

/// Wire format of the card's BLE image upload protocol
/// (`docs/ble-image-upload.md` in the firmware repo).
abstract final class UploadProtocol {
  static const advertisedName = 'TCG Proxy Card';

  static const serviceUuid = '7f0eca18-f2cb-47d8-a350-d535917badd7';
  static const controlUuid = 'f22a619d-bd0e-4974-ba6f-30fda3bcf5c8';
  static const dataUuid = '46639c60-7777-461a-b888-68f51edd3f5d';

  static const preferredMtu = 517;
  static const frameFormat = 0x01;

  static const _startOpcode = 0x01;
  static const _commitOpcode = 0x02;
  static const _abortOpcode = 0x03;
  static const _attHeaderLength = 3;
  static const _maxAttributeLength = 512;
  static const _offsetLength = 4;

  static Uint8List start({
    int size = PanelFrame.sizeInBytes,
    required int crc32,
  }) {
    final message = ByteData(10)
      ..setUint8(0, _startOpcode)
      ..setUint8(1, frameFormat)
      ..setUint32(2, size, Endian.little)
      ..setUint32(6, crc32, Endian.little);
    return message.buffer.asUint8List();
  }

  static Uint8List commit() => Uint8List.fromList([_commitOpcode]);

  static Uint8List abort() => Uint8List.fromList([_abortOpcode]);

  static Uint8List dataChunk(int offset, List<int> bytes) {
    final chunk = Uint8List(_offsetLength + bytes.length);
    ByteData.sublistView(chunk).setUint32(0, offset, Endian.little);
    chunk.setRange(_offsetLength, chunk.length, bytes);
    return chunk;
  }

  /// Frame bytes that fit in one data write at the given ATT MTU.
  static int chunkPayloadSize(int mtu) {
    final attributeLength = (mtu - _attHeaderLength).clamp(
      0,
      _maxAttributeLength,
    );
    final payload = attributeLength - _offsetLength;
    if (payload < 1) {
      throw ArgumentError.value(mtu, 'mtu', 'too small for a data chunk');
    }
    return payload;
  }
}

enum StatusEvent {
  ready(0x01),
  progress(0x02),
  verified(0x03),
  displayed(0x04),
  error(0xFF);

  const StatusEvent(this.id);

  final int id;
}

class StatusNotification {
  const StatusNotification(this.event, {this.code = 0, this.value = 0});

  static const length = 6;

  /// Returns null for anything that isn't a well-formed status notification.
  static StatusNotification? parse(List<int> bytes) {
    if (bytes.length != length) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final id = data.getUint8(0);
    final event = StatusEvent.values.where((e) => e.id == id).firstOrNull;
    if (event == null) return null;
    return StatusNotification(
      event,
      code: data.getUint8(1),
      value: data.getUint32(2, Endian.little),
    );
  }

  final StatusEvent event;
  final int code;
  final int value;

  Uint8List encode() {
    final data = ByteData(length)
      ..setUint8(0, event.id)
      ..setUint8(1, code)
      ..setUint32(2, value, Endian.little);
    return data.buffer.asUint8List();
  }

  @override
  bool operator ==(Object other) =>
      other is StatusNotification &&
      other.event == event &&
      other.code == code &&
      other.value == value;

  @override
  int get hashCode => Object.hash(event, code, value);

  @override
  String toString() => 'StatusNotification($event, code: $code, value: $value)';
}

enum DeviceErrorCode {
  invalidMessage(0x01, 'INVALID_MESSAGE'),
  unsupportedFormat(0x02, 'UNSUPPORTED_FORMAT'),
  invalidSize(0x03, 'INVALID_SIZE'),
  busy(0x04, 'BUSY'),
  noTransfer(0x05, 'NO_TRANSFER'),
  badOffset(0x06, 'BAD_OFFSET'),
  overflow(0x07, 'OVERFLOW'),
  incomplete(0x08, 'INCOMPLETE'),
  crcMismatch(0x09, 'CRC_MISMATCH'),
  noMemory(0x0A, 'NO_MEMORY'),
  storageFailed(0x0B, 'STORAGE_FAILED'),
  displayFailed(0x0C, 'DISPLAY_FAILED'),
  cooldown(0x0D, 'COOLDOWN');

  const DeviceErrorCode(this.id, this.wireName);

  final int id;
  final String wireName;

  static DeviceErrorCode? fromId(int id) =>
      values.where((code) => code.id == id).firstOrNull;
}
