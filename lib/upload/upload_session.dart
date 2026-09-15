import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import '../bluetooth/ble_service.dart';
import 'upload_failure.dart';
import 'upload_protocol.dart';

class UploadTimeouts {
  const UploadTimeouts({
    this.ready = const Duration(seconds: 10),
    this.verified = const Duration(seconds: 15),
    this.displayed = const Duration(seconds: 120),
    this.busyRetryDelay = const Duration(seconds: 5),
    this.busyRetries = 18,
  });

  final Duration ready;
  final Duration verified;
  final Duration displayed;
  final Duration busyRetryDelay;

  /// How many times to retry, [busyRetryDelay] apart, while the card answers
  /// BUSY.
  final int busyRetries;
}

enum UploadOutcome { displayed, displayedNotSaved }

const _control = BleCharacteristic(
  serviceUuid: UploadProtocol.serviceUuid,
  uuid: UploadProtocol.controlUuid,
);
const _data = BleCharacteristic(
  serviceUuid: UploadProtocol.serviceUuid,
  uuid: UploadProtocol.dataUuid,
);

/// Sends one frame to a connected card and follows it until displayed.
///
/// [run] throws an [UploadFailure] when the upload doesn't complete.
class UploadSession {
  UploadSession({
    required this.bluetooth,
    required this.deviceId,
    required this.frame,
    required this.crc32,
    this.timeouts = const UploadTimeouts(),
  });

  final BleService bluetooth;
  final String deviceId;
  final Uint8List frame;
  final int crc32;
  final UploadTimeouts timeouts;

  final _inbox = _StatusInbox();
  bool _transferActive = false;
  bool _refreshStarted = false;
  bool _writeWithoutResponse = true;

  bool get refreshStarted => _refreshStarted;

  /// Stops the upload unless the card has already started refreshing.
  void cancel() {
    if (!_refreshStarted) _inbox.interrupt(const UploadCancelled());
  }

  Future<UploadOutcome> run({
    void Function(int bytesSent, int totalBytes)? onProgress,
    void Function()? onVerified,
  }) async {
    final subscriptions = [
      bluetooth
          .notifications(deviceId, _control)
          .listen(
            _onNotification,
            onError: (Object e) => _inbox.interrupt(BluetoothFailure(e)),
          ),
      bluetooth.disconnections
          .where((id) => id == deviceId)
          .listen(
            (_) => _inbox.interrupt(
              DisconnectedFailure(refreshStarted: _refreshStarted),
            ),
          ),
    ];
    try {
      await _ble(
        () => bluetooth.setNotifications(deviceId, _control, enabled: true),
      );
      final mtu = await _ble(() => bluetooth.mtu(deviceId));
      await _transferUntilVerified(
        UploadProtocol.chunkPayloadSize(mtu),
        onProgress,
      );
      onVerified?.call();
      final displayed = await _expect(
        StatusEvent.displayed,
        timeouts.displayed,
        'the display to refresh',
      );
      return displayed.code == DeviceErrorCode.storageFailed.id
          ? UploadOutcome.displayedNotSaved
          : UploadOutcome.displayed;
    } on UploadCancelled {
      if (_transferActive) await _abort();
      rethrow;
    } finally {
      for (final subscription in subscriptions) {
        subscription.cancel().ignore();
      }
      bluetooth.setNotifications(deviceId, _control, enabled: false).ignore();
    }
  }

  Future<void> _transferUntilVerified(
    int chunkSize,
    void Function(int, int)? onProgress,
  ) async {
    var retries = 0;
    while (true) {
      try {
        await _start();
        await _sendFrame(chunkSize, onProgress);
        await _commit();
        return;
      } on DeviceErrorFailure catch (failure) {
        if (failure.code != DeviceErrorCode.busy ||
            retries++ >= timeouts.busyRetries) {
          rethrow;
        }
        await _inbox.sleep(timeouts.busyRetryDelay);
      }
    }
  }

  Future<void> _start() async {
    _inbox.clear();
    _transferActive = true;
    await _writeControl(UploadProtocol.start(size: frame.length, crc32: crc32));
    await _expect(StatusEvent.ready, timeouts.ready, 'the card to get ready');
  }

  Future<void> _sendFrame(
    int chunkSize,
    void Function(int, int)? onProgress,
  ) async {
    onProgress?.call(0, frame.length);
    for (var offset = 0; offset < frame.length; offset += chunkSize) {
      _inbox.throwIfInterrupted();
      _checkForErrors();
      final end = min(offset + chunkSize, frame.length);
      await _writeData(
        UploadProtocol.dataChunk(
          offset,
          Uint8List.sublistView(frame, offset, end),
        ),
      );
      onProgress?.call(end, frame.length);
    }
  }

  Future<void> _commit() async {
    _checkForErrors();
    await _writeControl(UploadProtocol.commit());
    await _expect(
      StatusEvent.verified,
      timeouts.verified,
      'the card to verify the image',
    );
    _transferActive = false;
    _refreshStarted = true;
  }

  Future<void> _abort() async {
    _transferActive = false;
    try {
      await bluetooth.write(deviceId, _control, UploadProtocol.abort());
    } on Exception {
      // The upload is over either way; the card also drops it on disconnect.
    }
  }

  void _onNotification(List<int> bytes) {
    final notification = StatusNotification.parse(bytes);
    if (notification != null) _inbox.add(notification);
  }

  void _checkForErrors() {
    for (var n = _inbox.take(); n != null; n = _inbox.take()) {
      _throwIfError(n);
    }
  }

  Future<StatusNotification> _expect(
    StatusEvent event,
    Duration timeout,
    String waitingFor,
  ) async {
    final notification = await _inbox.next(
      (n) => n.event == event || n.event == StatusEvent.error,
      timeout,
    );
    if (notification == null) throw UploadTimeoutFailure(waitingFor, timeout);
    _throwIfError(notification);
    return notification;
  }

  void _throwIfError(StatusNotification notification) {
    if (notification.event != StatusEvent.error) return;
    _transferActive = false;
    throw DeviceErrorFailure(notification.code, notification.value);
  }

  Future<void> _writeControl(Uint8List message) =>
      _ble(() => bluetooth.write(deviceId, _control, message));

  Future<void> _writeData(Uint8List chunk) async {
    if (_writeWithoutResponse) {
      try {
        await bluetooth.write(deviceId, _data, chunk, withoutResponse: true);
        return;
      } on BleException {
        _inbox.throwIfInterrupted();
        _writeWithoutResponse = false;
      }
    }
    await _ble(() => bluetooth.write(deviceId, _data, chunk));
  }

  /// Runs a Bluetooth call, preferring the reason the upload was interrupted
  /// (such as a disconnect) over the plugin error it caused.
  Future<T> _ble<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      _inbox.throwIfInterrupted();
      return result;
    } on BleException catch (e) {
      _inbox.throwIfInterrupted();
      throw BluetoothFailure(e);
    }
  }
}

class _StatusInbox {
  final _queue = Queue<StatusNotification>();
  Completer<void>? _wakeUp;
  UploadFailure? _interruption;

  void add(StatusNotification notification) {
    _queue.add(notification);
    _wake();
  }

  void interrupt(UploadFailure reason) {
    _interruption ??= reason;
    _wake();
  }

  void throwIfInterrupted() {
    if (_interruption case final reason?) throw reason;
  }

  StatusNotification? take() => _queue.isEmpty ? null : _queue.removeFirst();

  void clear() => _queue.clear();

  /// The first notification [isWanted] accepts, dropping the others, or null
  /// if none arrives within [timeout].
  Future<StatusNotification?> next(
    bool Function(StatusNotification) isWanted,
    Duration timeout,
  ) async {
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      _wake();
    });
    try {
      while (true) {
        throwIfInterrupted();
        for (var n = take(); n != null; n = take()) {
          if (isWanted(n)) return n;
        }
        if (timedOut) return null;
        await (_wakeUp = Completer<void>()).future;
      }
    } finally {
      timer.cancel();
    }
  }

  /// Waits for [duration] unless the upload is interrupted first.
  Future<void> sleep(Duration duration) async {
    final timer = Timer(duration, _wake);
    try {
      while (timer.isActive) {
        throwIfInterrupted();
        await (_wakeUp = Completer<void>()).future;
      }
      throwIfInterrupted();
    } finally {
      timer.cancel();
    }
  }

  void _wake() {
    final wakeUp = _wakeUp;
    _wakeUp = null;
    if (wakeUp != null && !wakeUp.isCompleted) wakeUp.complete();
  }
}
