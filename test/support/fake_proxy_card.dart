import 'dart:async';
import 'dart:typed_data';

import 'package:tcg_proxy_card_app/upload/panel_frame.dart';
import 'package:tcg_proxy_card_app/upload/upload_protocol.dart';

import 'fake_ble_service.dart';

/// Plays the card's side of the upload protocol on a [FakeBleService].
class FakeProxyCard {
  FakeProxyCard(this.bluetooth) {
    bluetooth.services = {UploadProtocol.serviceUuid};
    bluetooth.onWrite = _onWrite;
  }

  final FakeBleService bluetooth;

  /// Replies to successive STARTs; READY once these run out.
  final List<StatusNotification?> startReplies = [];

  /// Replaces VERIFIED as the reply to COMMIT; null stays silent.
  StatusNotification? Function()? commitReply;

  /// Sent after this many data chunks instead of carrying on.
  final Map<int, StatusNotification> chunkReplies = {};

  bool displayAfterVerify = true;
  int displayedCode = 0;

  int starts = 0;
  int commits = 0;
  int aborts = 0;
  int chunks = 0;
  final received = BytesBuilder();

  void send(StatusNotification notification) =>
      scheduleMicrotask(() => bluetooth.notify(notification.encode()));

  void display({int code = 0}) =>
      send(StatusNotification(StatusEvent.displayed, code: code));

  void _onWrite(FakeWrite write) {
    switch (write.characteristic.uuid) {
      case UploadProtocol.controlUuid:
        _onControl(write.value);
      case UploadProtocol.dataUuid:
        _onData(write.value);
    }
  }

  void _onControl(List<int> message) {
    switch (message.first) {
      case 0x01:
        starts++;
        received.clear();
        final reply = startReplies.isEmpty
            ? const StatusNotification(
                StatusEvent.ready,
                value: PanelFrame.sizeInBytes,
              )
            : startReplies.removeAt(0);
        if (reply != null) send(reply);
      case 0x02:
        commits++;
        final reply = commitReply != null
            ? commitReply!()
            : const StatusNotification(
                StatusEvent.verified,
                value: PanelFrame.sizeInBytes,
              );
        if (reply == null) return;
        send(reply);
        if (reply.event == StatusEvent.verified && displayAfterVerify) {
          display(code: displayedCode);
        }
      case 0x03:
        aborts++;
    }
  }

  void _onData(List<int> chunk) {
    chunks++;
    received.add(chunk.sublist(4));
    if (chunkReplies[chunks] case final reply?) send(reply);
  }
}
