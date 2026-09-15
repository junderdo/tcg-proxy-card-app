import '../bluetooth/ble_service.dart';
import 'panel_cooldown.dart';
import 'panel_frame.dart';
import 'upload_protocol.dart';

sealed class UploadFailure implements Exception {
  const UploadFailure();

  String get message;

  @override
  String toString() => message;
}

/// An ERROR notification from the card.
class DeviceErrorFailure extends UploadFailure {
  const DeviceErrorFailure(this.codeId, this.value);

  final int codeId;
  final int value;

  DeviceErrorCode? get code => DeviceErrorCode.fromId(codeId);

  @override
  String get message {
    final hexCode =
        '0x${codeId.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    final name = code?.wireName ?? 'UNKNOWN';
    return '$_description (error $hexCode $name)';
  }

  String get _description => switch (code) {
    DeviceErrorCode.invalidMessage =>
      'The card rejected a malformed message from the app.',
    DeviceErrorCode.unsupportedFormat =>
      "The card doesn't support image format $value.",
    DeviceErrorCode.invalidSize =>
      'The card expects an image of $value bytes, '
          'not ${PanelFrame.sizeInBytes}.',
    DeviceErrorCode.busy =>
      'The card is still refreshing its display. Try again in a few seconds.',
    DeviceErrorCode.noTransfer =>
      'The card had no upload in progress, so it dropped the data.',
    DeviceErrorCode.badOffset =>
      'Image data arrived out of order after the card had received '
          '$value bytes.',
    DeviceErrorCode.overflow =>
      'The app sent more than the declared $value bytes.',
    DeviceErrorCode.incomplete =>
      'The card received only $value of ${PanelFrame.sizeInBytes} bytes.',
    DeviceErrorCode.crcMismatch =>
      'The image was corrupted in transit (the card computed CRC '
          '0x${value.toRadixString(16).padLeft(8, '0')}).',
    DeviceErrorCode.noMemory =>
      "The card doesn't have enough free memory for the image.",
    DeviceErrorCode.storageFailed => "The image couldn't be saved on the card.",
    DeviceErrorCode.displayFailed => "The card's display failed to refresh.",
    DeviceErrorCode.cooldown =>
      'The display refreshed too recently. Wait '
          '${formatCountdown(Duration(seconds: value))} before uploading '
          'again; refreshing too often wears out the panel.',
    null => 'The card reported an unknown error (value $value).',
  };
}

class UploadTimeoutFailure extends UploadFailure {
  const UploadTimeoutFailure(this.waitingFor, this.timeout);

  final String waitingFor;
  final Duration timeout;

  @override
  String get message =>
      'Timed out after ${timeout.inSeconds} s waiting for $waitingFor.';
}

class DisconnectedFailure extends UploadFailure {
  const DisconnectedFailure({required this.refreshStarted});

  final bool refreshStarted;

  @override
  String get message => refreshStarted
      ? 'The card disconnected while refreshing. It should still show the '
            "new image, but the app couldn't confirm it."
      : 'The card disconnected during the upload. Reconnect and try again.';
}

class BluetoothFailure extends UploadFailure {
  const BluetoothFailure(this.cause);

  final Object cause;

  @override
  String get message =>
      'Bluetooth error: ${cause is BleException ? (cause as BleException).message : cause}';
}

class UploadCancelled extends UploadFailure {
  const UploadCancelled();

  @override
  String get message => 'Upload cancelled.';
}
