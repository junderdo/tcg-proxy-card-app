import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/upload/upload_protocol.dart';

void main() {
  group('control messages', () {
    test('START carries format, size and CRC little-endian', () {
      expect(UploadProtocol.start(crc32: 0x11223344), [
        0x01,
        0x01,
        0xC0, 0xD4, 0x01, 0x00, // 120000
        0x44, 0x33, 0x22, 0x11,
      ]);
    });

    test('COMMIT and ABORT are single opcodes', () {
      expect(UploadProtocol.commit(), [0x02]);
      expect(UploadProtocol.abort(), [0x03]);
    });
  });

  test('data chunks are prefixed with their little-endian offset', () {
    expect(UploadProtocol.dataChunk(0x01020304, [9, 8, 7]), [
      0x04,
      0x03,
      0x02,
      0x01,
      9,
      8,
      7,
    ]);
    expect(UploadProtocol.dataChunk(0, []), [0, 0, 0, 0]);
  });

  group('chunk payload size', () {
    test('is the MTU minus ATT and offset headers', () {
      expect(UploadProtocol.chunkPayloadSize(23), 16);
      expect(UploadProtocol.chunkPayloadSize(185), 178);
      expect(UploadProtocol.chunkPayloadSize(247), 240);
    });

    test('is capped by the 512-byte attribute limit', () {
      expect(UploadProtocol.chunkPayloadSize(515), 508);
      expect(UploadProtocol.chunkPayloadSize(517), 508);
      expect(UploadProtocol.chunkPayloadSize(1024), 508);
    });

    test('rejects an MTU too small for any data', () {
      expect(() => UploadProtocol.chunkPayloadSize(7), throwsArgumentError);
    });
  });

  group('StatusNotification.parse', () {
    test('reads event, code and little-endian value', () {
      expect(
        StatusNotification.parse([0x02, 0x00, 0x00, 0x20, 0x00, 0x00]),
        const StatusNotification(StatusEvent.progress, value: 8192),
      );
      expect(
        StatusNotification.parse([0xFF, 0x0D, 0xB4, 0x00, 0x00, 0x00]),
        const StatusNotification(StatusEvent.error, code: 0x0D, value: 180),
      );
      expect(
        StatusNotification.parse([0x04, 0x0B, 0, 0, 0, 0]),
        const StatusNotification(StatusEvent.displayed, code: 0x0B),
      );
    });

    test('rejects wrong lengths and unknown events', () {
      expect(StatusNotification.parse([0x01, 0, 0, 0, 0]), isNull);
      expect(StatusNotification.parse([0x01, 0, 0, 0, 0, 0, 0]), isNull);
      expect(StatusNotification.parse([0x09, 0, 0, 0, 0, 0]), isNull);
    });

    test('round-trips through encode', () {
      const ready = StatusNotification(StatusEvent.ready, value: 120000);
      expect(StatusNotification.parse(ready.encode()), ready);
    });
  });

  test('every error code has a distinct wire id', () {
    expect(
      DeviceErrorCode.values.map((code) => code.id).toSet(),
      hasLength(DeviceErrorCode.values.length),
    );
    expect(DeviceErrorCode.fromId(0x0D), DeviceErrorCode.cooldown);
    expect(DeviceErrorCode.fromId(0x42), isNull);
  });
}
