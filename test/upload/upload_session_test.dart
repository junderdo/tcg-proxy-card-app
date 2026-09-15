import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/bluetooth/ble_service.dart';
import 'package:tcg_proxy_card_app/upload/panel_frame.dart';
import 'package:tcg_proxy_card_app/upload/upload_failure.dart';
import 'package:tcg_proxy_card_app/upload/upload_protocol.dart';
import 'package:tcg_proxy_card_app/upload/upload_session.dart';

import '../support/fake_ble_service.dart';
import '../support/fake_proxy_card.dart';
import '../support/upload_harness.dart';

void main() {
  const deviceId = 'AA:01';
  final frame = Uint8List.fromList(
    List.generate(PanelFrame.sizeInBytes, (i) => (i * 31) & 0x66),
  );
  final crc = PanelFrame.crc32(frame);

  late FakeBleService bluetooth;
  late FakeProxyCard card;

  setUp(() {
    bluetooth = FakeBleService();
    card = FakeProxyCard(bluetooth);
  });

  UploadSession session({UploadTimeouts timeouts = testTimeouts}) =>
      UploadSession(
        bluetooth: bluetooth,
        deviceId: deviceId,
        frame: frame,
        crc32: crc,
        timeouts: timeouts,
      );

  StatusNotification error(DeviceErrorCode code, [int value = 0]) =>
      StatusNotification(StatusEvent.error, code: code.id, value: value);

  Matcher failsWith(DeviceErrorCode code) =>
      throwsA(isA<DeviceErrorFailure>().having((f) => f.code, 'code', code));

  test('sends the frame and waits for the display', () async {
    final progress = <int>[];
    var verifiedAt = -1;

    final outcome = await session().run(
      onProgress: (sent, total) {
        expect(total, PanelFrame.sizeInBytes);
        progress.add(sent);
      },
      onVerified: () => verifiedAt = card.commits,
    );

    expect(outcome, UploadOutcome.displayed);
    expect(card.received.toBytes(), frame);
    expect(
      bluetooth.writesTo(UploadProtocol.controlUuid).first.value,
      UploadProtocol.start(crc32: crc),
    );
    expect(card.chunks, (PanelFrame.sizeInBytes / 508).ceil());
    expect(
      bluetooth
          .writesTo(UploadProtocol.dataUuid)
          .every((w) => w.withoutResponse),
      isTrue,
    );
    expect(progress.first, 0);
    expect(progress.last, PanelFrame.sizeInBytes);
    expect(verifiedAt, 1);
    expect(bluetooth.notificationToggles, [true, false]);
  });

  test('offsets each chunk by the bytes sent before it', () async {
    bluetooth.negotiatedMtu = 185;

    await session().run();

    final chunks = bluetooth.writesTo(UploadProtocol.dataUuid);
    expect(chunks[0].value.sublist(0, 4), [0, 0, 0, 0]);
    expect(chunks[1].value.sublist(0, 4), [178, 0, 0, 0]);
    expect(chunks[0].value, hasLength(182));
    expect(card.received.toBytes(), frame);
  });

  test('falls back to write with response when writes fail', () async {
    bluetooth.writeWithoutResponseError = const BleException('not ready');

    await session().run();

    expect(card.received.toBytes(), frame);
    expect(
      bluetooth.writesTo(UploadProtocol.dataUuid).any((w) => w.withoutResponse),
      isFalse,
    );
  });

  test('reports a display that was shown but not saved', () async {
    card.displayedCode = DeviceErrorCode.storageFailed.id;

    expect(await session().run(), UploadOutcome.displayedNotSaved);
  });

  group('BUSY', () {
    test('waits and retries START', () async {
      card.startReplies.addAll([
        error(DeviceErrorCode.busy),
        error(DeviceErrorCode.busy),
      ]);

      expect(await session().run(), UploadOutcome.displayed);
      expect(card.starts, 3);
      expect(card.received.toBytes(), frame);
    });

    test('restarts the transfer when COMMIT finds the card busy', () async {
      var commits = 0;
      card.commitReply = () => commits++ == 0
          ? error(DeviceErrorCode.busy)
          : const StatusNotification(StatusEvent.verified);

      expect(await session().run(), UploadOutcome.displayed);
      expect(card.starts, 2);
    });

    test('gives up after the retry limit', () async {
      card.startReplies.addAll(List.filled(10, error(DeviceErrorCode.busy)));

      await expectLater(session().run(), failsWith(DeviceErrorCode.busy));
      expect(card.starts, testTimeouts.busyRetries + 1);
    });
  });

  group('device errors', () {
    for (final code in DeviceErrorCode.values) {
      if (code == DeviceErrorCode.busy) continue;
      test(
        '${code.wireName} ends the upload with its code and value',
        () async {
          card.startReplies.add(error(code, 96000));

          final failure = await session().run().then<Object?>(
            (_) => null,
            onError: (Object e) => e,
          );

          expect(failure, isA<DeviceErrorFailure>());
          failure as DeviceErrorFailure;
          expect(failure.code, code);
          expect(failure.value, 96000);
          final hex = code.id.toRadixString(16).padLeft(2, '0').toUpperCase();
          expect(failure.message, contains('0x$hex ${code.wireName}'));
          expect(card.chunks, 0);
        },
      );
    }

    test('messages include meaningful values', () {
      expect(
        DeviceErrorFailure(DeviceErrorCode.cooldown.id, 95).message,
        contains('Wait 1:35'),
      );
      expect(
        DeviceErrorFailure(DeviceErrorCode.invalidSize.id, 96000).message,
        contains('96000 bytes'),
      );
      expect(
        DeviceErrorFailure(DeviceErrorCode.crcMismatch.id, 0xBEEF).message,
        contains('0x0000beef'),
      );
      expect(
        const DeviceErrorFailure(0x42, 1).message,
        contains('unknown error'),
      );
    });

    test('an error during the transfer stops sending', () async {
      card.chunkReplies[3] = error(DeviceErrorCode.badOffset, 1016);

      await expectLater(session().run(), failsWith(DeviceErrorCode.badOffset));
      expect(card.chunks, lessThan(10));
      expect(card.commits, 0);
      expect(card.aborts, 0);
    });

    test('COOLDOWN at COMMIT carries the seconds left', () async {
      card.commitReply = () => error(DeviceErrorCode.cooldown, 42);

      await expectLater(
        session().run(),
        throwsA(isA<DeviceErrorFailure>().having((f) => f.value, 'value', 42)),
      );
    });

    test('a failed refresh after VERIFIED is reported', () async {
      card.displayAfterVerify = false;
      final upload = session();

      final result = upload.run(
        onVerified: () => card.send(error(DeviceErrorCode.displayFailed)),
      );

      await expectLater(result, failsWith(DeviceErrorCode.displayFailed));
      expect(upload.refreshStarted, isTrue);
    });
  });

  group('cancel', () {
    test('mid-transfer sends ABORT', () async {
      final upload = session();

      final result = upload.run(
        onProgress: (sent, _) {
          if (sent > 10000) upload.cancel();
        },
      );

      await expectLater(result, throwsA(isA<UploadCancelled>()));
      expect(card.aborts, 1);
      expect(card.commits, 0);
      expect(card.chunks, lessThan(30));
      expect(
        bluetooth.writesTo(UploadProtocol.controlUuid).last.value,
        UploadProtocol.abort(),
      );
    });

    test('while waiting out BUSY stops without ABORT', () async {
      card.startReplies.add(error(DeviceErrorCode.busy));
      final upload = session(
        timeouts: const UploadTimeouts(busyRetryDelay: Duration(seconds: 30)),
      );

      final result = upload.run();
      await pumpEventQueue();
      upload.cancel();

      await expectLater(result, throwsA(isA<UploadCancelled>()));
      expect(card.starts, 1);
      expect(card.aborts, 0);
    });

    test('is ignored once the card is refreshing', () async {
      card.displayAfterVerify = false;
      final upload = session();

      final result = upload.run(onVerified: upload.cancel);
      await pumpEventQueue();
      card.display();

      expect(await result, UploadOutcome.displayed);
      expect(card.aborts, 0);
    });
  });

  group('disconnect', () {
    test('mid-transfer fails with a clear error', () async {
      final upload = session();

      final result = upload.run(
        onProgress: (sent, _) {
          if (sent > 5000 && sent < 6000) {
            bluetooth.emitDisconnection(deviceId);
            bluetooth.writeWithoutResponseError = const BleException('gone');
          }
        },
      );

      await expectLater(
        result,
        throwsA(
          isA<DisconnectedFailure>()
              .having((f) => f.refreshStarted, 'refreshStarted', isFalse)
              .having((f) => f.message, 'message', contains('disconnected')),
        ),
      );
    });

    test('of another device is ignored', () async {
      final result = session().run(
        onProgress: (sent, _) {
          if (sent == 0) bluetooth.emitDisconnection('BB:02');
        },
      );

      expect(await result, UploadOutcome.displayed);
    });

    test('while refreshing says the image should still appear', () async {
      card.displayAfterVerify = false;

      final result = session().run(
        onVerified: () => bluetooth.emitDisconnection(deviceId),
      );

      await expectLater(
        result,
        throwsA(
          isA<DisconnectedFailure>().having(
            (f) => f.refreshStarted,
            'refreshStarted',
            isTrue,
          ),
        ),
      );
    });
  });

  group('timeouts', () {
    const short = UploadTimeouts(
      ready: Duration(milliseconds: 20),
      verified: Duration(milliseconds: 20),
      displayed: Duration(milliseconds: 20),
    );

    Matcher timesOutWaitingFor(String what) => throwsA(
      isA<UploadTimeoutFailure>().having(
        (f) => f.message,
        'message',
        contains(what),
      ),
    );

    test('waiting for READY', () async {
      card.startReplies.add(null);
      await expectLater(
        session(timeouts: short).run(),
        timesOutWaitingFor('ready'),
      );
    });

    test('waiting for VERIFIED', () async {
      card.commitReply = () => null;
      await expectLater(
        session(timeouts: short).run(),
        timesOutWaitingFor('verify'),
      );
    });

    test('waiting for DISPLAYED', () async {
      card.displayAfterVerify = false;
      await expectLater(
        session(timeouts: short).run(),
        timesOutWaitingFor('refresh'),
      );
    });

    test('progress notifications do not extend the wait', () async {
      card.startReplies.add(null);
      final ticker = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => card.send(const StatusNotification(StatusEvent.progress)),
      );
      addTearDown(ticker.cancel);

      await expectLater(
        session(timeouts: short).run(),
        timesOutWaitingFor('ready'),
      );
    });

    test('allow at least 90 s for the refresh by default', () {
      expect(
        const UploadTimeouts().displayed,
        greaterThanOrEqualTo(const Duration(seconds: 90)),
      );
    });
  });

  test('a Bluetooth failure is reported', () async {
    bluetooth.onWrite = (_) => throw const BleException('GATT error 133');

    await expectLater(
      session().run(),
      throwsA(
        isA<BluetoothFailure>().having(
          (f) => f.message,
          'message',
          contains('GATT error 133'),
        ),
      ),
    );
  });
}
