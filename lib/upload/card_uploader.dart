import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../bluetooth/ble_devices_controller.dart';
import '../bluetooth/ble_service.dart';
import 'panel_cooldown.dart';
import 'panel_image.dart';
import 'upload_failure.dart';
import 'upload_protocol.dart';
import 'upload_session.dart';

typedef ImageDownloader = Future<Uint8List> Function(String url);

Future<Uint8List> fetchImageBytes(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw http.ClientException(
      'Image download failed (HTTP ${response.statusCode})',
      Uri.parse(url),
    );
  }
  return response.bodyBytes;
}

/// The replaceable parts of uploading, so tests can swap them out.
class UploadEnvironment {
  const UploadEnvironment({
    this.cooldownStore = const SharedPreferencesCooldownStore(),
    this.clock = DateTime.now,
    this.downloadImage = fetchImageBytes,
    this.convertImage = convertToPanelImageInBackground,
    this.timeouts = const UploadTimeouts(),
  });

  final CooldownStore cooldownStore;
  final Clock clock;
  final ImageDownloader downloadImage;
  final PanelImageConverter convertImage;
  final UploadTimeouts timeouts;
}

sealed class UploadReadiness {
  const UploadReadiness();
}

class NoDeviceConnected extends UploadReadiness {
  const NoDeviceConnected({required this.bluetoothSupported});

  final bool bluetoothSupported;
}

class IncompatibleDevice extends UploadReadiness {
  const IncompatibleDevice(this.device);

  final BleDevice device;
}

class DeviceCheckFailed extends UploadReadiness {
  const DeviceCheckFailed(this.device, this.error);

  final BleDevice device;
  final BluetoothFailure error;
}

class DeviceCoolingDown extends UploadReadiness {
  const DeviceCoolingDown(this.device);

  final BleDevice device;
}

class ReadyToUpload extends UploadReadiness {
  const ReadyToUpload(this.device);

  final BleDevice device;
}

/// Sends card images to connected proxy cards. Shared across the app so the
/// connection and cooldowns outlive any one screen.
class CardUploader {
  CardUploader({
    required this.bluetooth,
    required this.devices,
    required this.cooldown,
    this.environment = const UploadEnvironment(),
  });

  final BleService bluetooth;
  final BleDevicesController devices;
  final PanelCooldown cooldown;
  final UploadEnvironment environment;

  Listenable get changes => Listenable.merge([devices, cooldown]);

  BleDevice? get connectedDevice => devices.connectedDevices.firstOrNull;

  Future<UploadReadiness> checkReadiness() async {
    await Future.wait([devices.initialize(), cooldown.load()]);
    final device = connectedDevice;
    if (device == null) {
      return NoDeviceConnected(
        bluetoothSupported: devices.status != BluetoothStatus.unsupported,
      );
    }
    if (cooldown.isCoolingDown(device.id)) return DeviceCoolingDown(device);
    try {
      final services = await bluetooth.discoverServices(device.id);
      return services.contains(UploadProtocol.serviceUuid)
          ? ReadyToUpload(device)
          : IncompatibleDevice(device);
    } on BleException catch (e) {
      return DeviceCheckFailed(device, BluetoothFailure(e));
    }
  }

  CardUploadController prepareUpload({
    required BleDevice device,
    required String imageUrl,
  }) => CardUploadController._(this, device, imageUrl);
}

enum UploadStage {
  preparing,
  confirming,
  transferring,
  refreshing,
  displayed,
  displayedNotSaved,
  failed,
  cancelled,
}

/// One upload of one card image, from conversion to the panel refresh.
class CardUploadController extends ChangeNotifier {
  CardUploadController._(this._uploader, this.device, this.imageUrl);

  final CardUploader _uploader;
  final BleDevice device;
  final String imageUrl;
  UploadSession? _session;
  bool _disposed = false;

  UploadStage stage = UploadStage.preparing;
  PanelImage? image;
  int bytesSent = 0;
  int totalBytes = 0;
  String? errorMessage;

  bool get canCancel =>
      stage == UploadStage.preparing ||
      stage == UploadStage.confirming ||
      stage == UploadStage.transferring;

  bool get isFinished => switch (stage) {
    UploadStage.displayed ||
    UploadStage.displayedNotSaved ||
    UploadStage.failed ||
    UploadStage.cancelled => true,
    _ => false,
  };

  double get progress => totalBytes == 0 ? 0 : bytesSent / totalBytes;

  PanelCooldown get _cooldown => _uploader.cooldown;
  UploadEnvironment get _environment => _uploader.environment;

  Future<void> prepare() async {
    try {
      final encoded = await _environment.downloadImage(imageUrl);
      final converted = await _environment.convertImage(encoded);
      if (stage != UploadStage.preparing) return;
      image = converted;
      _setStage(UploadStage.confirming);
    } on Exception catch (e) {
      if (stage != UploadStage.preparing) return;
      _fail("Couldn't prepare the card image: $e");
    }
  }

  Future<void> send() async {
    final image = this.image;
    if (stage != UploadStage.confirming || image == null) return;
    if (_cooldown.isCoolingDown(device.id)) {
      _fail(
        'Wait ${formatCountdown(_cooldown.remainingFor(device.id))} before '
        'uploading again; refreshing too often wears out the panel.',
      );
      return;
    }
    final session = _session = UploadSession(
      bluetooth: _uploader.bluetooth,
      deviceId: device.id,
      frame: image.frame,
      crc32: image.crc32,
      timeouts: _environment.timeouts,
    );
    totalBytes = image.frame.length;
    _setStage(UploadStage.transferring);
    try {
      final outcome = await session.run(
        onProgress: _onProgress,
        onVerified: _onVerified,
      );
      await _cooldown.recordRefresh(device.id);
      _setStage(
        outcome == UploadOutcome.displayed
            ? UploadStage.displayed
            : UploadStage.displayedNotSaved,
      );
    } on UploadCancelled {
      _setStage(UploadStage.cancelled);
    } on UploadFailure catch (failure) {
      await _recordCooldownAfter(failure, session);
      _fail(failure.message);
    }
  }

  void cancel() {
    switch (stage) {
      case UploadStage.preparing || UploadStage.confirming:
        _setStage(UploadStage.cancelled);
      case UploadStage.transferring:
        _session?.cancel();
      default:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _session?.cancel();
    super.dispose();
  }

  void _onProgress(int sent, int total) {
    bytesSent = sent;
    totalBytes = total;
    _notify();
  }

  void _onVerified() {
    _cooldown.recordRefresh(device.id);
    _setStage(UploadStage.refreshing);
  }

  Future<void> _recordCooldownAfter(
    UploadFailure failure,
    UploadSession session,
  ) async {
    if (failure case DeviceErrorFailure(
      code: DeviceErrorCode.cooldown,
      :final value,
    )) {
      await _cooldown.syncFromDevice(device.id, Duration(seconds: value));
    } else if (session.refreshStarted) {
      // The refresh ends some time after VERIFIED; restart the count now.
      await _cooldown.recordRefresh(device.id);
    }
  }

  void _fail(String message) {
    errorMessage = message;
    _setStage(UploadStage.failed);
  }

  void _setStage(UploadStage newStage) {
    stage = newStage;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
