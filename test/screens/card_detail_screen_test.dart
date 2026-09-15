import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/scryfall/models.dart';
import 'package:tcg_proxy_card_app/screens/card_detail_screen.dart';
import 'package:tcg_proxy_card_app/upload/panel_frame.dart';
import 'package:tcg_proxy_card_app/upload/upload_protocol.dart';

import '../support/fake_proxy_card.dart';
import '../support/fake_scryfall.dart';
import '../support/upload_harness.dart';

void main() {
  const deviceId = 'AA:01';
  final card = ScryfallCard.fromJson(cardJson('abc'));

  late UploadHarness harness;
  late FakeProxyCard proxyCard;
  late int showDevicesCalls;

  setUp(() {
    harness = UploadHarness();
    proxyCard = FakeProxyCard(harness.bluetooth);
    showDevicesCalls = 0;
  });

  tearDown(() => harness.dispose());

  Future<void> pumpDetail(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CardDetailScreen(
          card: card,
          uploader: harness.uploader,
          onShowDevices: () => showDevicesCalls++,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpFrames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump();
    }
  }

  Finder uploadButton() => find.byType(FilledButton).first;

  Future<void> tapUpload(WidgetTester tester) async {
    await tester.tap(uploadButton());
    await pumpFrames(tester);
  }

  Future<void> tapUploadAndSend(WidgetTester tester) async {
    await tapUpload(tester);
    expect(find.text('Send to TCG Proxy Card?'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await pumpFrames(tester);
  }

  StatusNotification error(DeviceErrorCode code, int value) =>
      StatusNotification(StatusEvent.error, code: code.id, value: value);

  void holdWritesAfter(int writes) {
    harness.bluetooth
      ..writeGate = Completer<void>()
      ..writesBeforeGate = writes;
  }

  testWidgets('shows the large card image with an Upload button below it', (
    tester,
  ) async {
    await pumpDetail(tester);

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, card.largeImageUrl);

    final upload = find.widgetWithText(FilledButton, 'Upload');
    expect(upload, findsOneWidget);
    expect(
      tester.getTopLeft(upload).dy,
      greaterThan(tester.getBottomLeft(find.byType(Image)).dy),
    );
  });

  testWidgets('Upload is a large full-width button that fits a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpDetail(tester);

    expect(tester.takeException(), isNull);
    final upload = tester.getRect(find.widgetWithText(FilledButton, 'Upload'));
    expect(upload.height, greaterThanOrEqualTo(56));
    expect(upload.width, 320 - 2 * 16);
    expect(upload.bottom, lessThanOrEqualTo(568));
    expect(find.byIcon(Icons.upload), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Upload')).style?.fontSize ??
          DefaultTextStyle.of(tester.element(find.text('Upload')))
              .style
              .fontSize,
      20,
    );
  });

  group('without a compatible device', () {
    testWidgets('explains that no card is connected and offers Devices', (
      tester,
    ) async {
      await pumpDetail(tester);

      await tapUpload(tester);

      expect(find.text('No card connected'), findsOneWidget);
      await tester.tap(find.text('Go to Devices'));
      await tester.pumpAndSettle();
      expect(showDevicesCalls, 1);
      expect(harness.downloads, isEmpty);
    });

    testWidgets('explains when the connected card lacks the upload service', (
      tester,
    ) async {
      harness.bluetooth.services = {'0000180d-0000-1000-8000-00805f9b34fb'};
      await harness.connect(deviceId);
      await pumpDetail(tester);

      await tapUpload(tester);

      expect(find.text("Can't upload to this device"), findsOneWidget);
      expect(
        find.textContaining(
          "TCG Proxy Card doesn't offer the image upload service",
        ),
        findsOneWidget,
      );
      expect(find.text('Go to Devices'), findsOneWidget);
      expect(harness.bluetooth.writes, isEmpty);
    });
  });

  group('cooldown', () {
    testWidgets('counts down on the button and blocks the upload', (
      tester,
    ) async {
      await harness.connect(deviceId);
      harness.store.saved[deviceId] = harness.clock.now.add(
        const Duration(seconds: 100),
      );
      await pumpDetail(tester);

      expect(find.text('Wait 1:40'), findsOneWidget);
      await tapUpload(tester);

      expect(find.text('Please wait before uploading'), findsOneWidget);
      expect(find.textContaining('wears out'), findsOneWidget);
      expect(find.text('1:40'), findsOneWidget);

      harness.clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1:39'), findsOneWidget);
      expect(find.text('Wait 1:39'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(harness.bluetooth.writes, isEmpty);
      expect(harness.downloads, isEmpty);

      harness.clock.advance(const Duration(seconds: 99));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Upload'), findsOneWidget);
    });

    testWidgets("syncs to the card's COOLDOWN reply", (tester) async {
      proxyCard.startReplies.add(error(DeviceErrorCode.cooldown, 95));
      await harness.connect(deviceId);
      await pumpDetail(tester);

      await tapUploadAndSend(tester);

      expect(find.text('Upload failed'), findsOneWidget);
      expect(find.textContaining('Wait 1:35 before uploading'), findsOneWidget);
      expect(find.textContaining('0x0D COOLDOWN'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await pumpFrames(tester);
      expect(find.text('Wait 1:35'), findsOneWidget);
    });
  });

  testWidgets('shows progress, then the refresh, then success', (tester) async {
    proxyCard.displayAfterVerify = false;
    await harness.connect(deviceId);
    await pumpDetail(tester);
    holdWritesAfter(40);

    await tapUploadAndSend(tester);

    expect(find.text('Uploading'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, closeTo(39 * 508 / PanelFrame.sizeInBytes, 0.001));
    expect(find.text('Sent 20 of 120 KB'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    harness.bluetooth.writeGate!.complete();
    await pumpFrames(tester, 30);

    expect(find.text('Refreshing display'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(find.text('Cancel'), findsNothing);

    proxyCard.display();
    await pumpFrames(tester);

    expect(find.text('Uploaded'), findsOneWidget);
    expect(find.text('The card is showing the new image.'), findsOneWidget);
    expect(proxyCard.received.toBytes(), testPanelImage.frame);
    expect(harness.downloads, [card.largeImageUrl]);
    await tester.tap(find.text('Done'));
    await pumpFrames(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Wait 3:00'), findsOneWidget);
  });

  testWidgets('warns when the image was shown but not saved', (tester) async {
    proxyCard.displayedCode = DeviceErrorCode.storageFailed.id;
    await harness.connect(deviceId);
    await pumpDetail(tester);

    await tapUploadAndSend(tester);

    expect(find.text('Shown but not saved'), findsOneWidget);
    expect(find.textContaining("won't survive a reboot"), findsOneWidget);
  });

  testWidgets('cancelling mid-transfer aborts and closes the dialog', (
    tester,
  ) async {
    await harness.connect(deviceId);
    await pumpDetail(tester);
    holdWritesAfter(10);
    await tapUploadAndSend(tester);

    await tester.tap(find.text('Cancel'));
    harness.bluetooth.writeGate!.complete();
    await pumpFrames(tester);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(proxyCard.aborts, 1);
    expect(proxyCard.commits, 0);
    expect(find.text('Upload'), findsOneWidget);
  });

  group('errors', () {
    testWidgets('shows the device error with its code and value', (
      tester,
    ) async {
      proxyCard.startReplies.add(error(DeviceErrorCode.invalidSize, 96000));
      await harness.connect(deviceId);
      await pumpDetail(tester);

      await tapUploadAndSend(tester);

      expect(find.text('Upload failed'), findsOneWidget);
      expect(
        find.textContaining('expects an image of 96000 bytes'),
        findsOneWidget,
      );
      expect(find.textContaining('0x03 INVALID_SIZE'), findsOneWidget);
      expect(find.text('Upload'), findsOneWidget);
    });

    testWidgets('shows a timeout', (tester) async {
      proxyCard.startReplies.add(null);
      await harness.connect(deviceId);
      await pumpDetail(tester);

      await tapUploadAndSend(tester);
      await tester.pump(testTimeouts.ready);
      await pumpFrames(tester);

      expect(
        find.text('Timed out after 1 s waiting for the card to get ready.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a disconnect during the transfer', (tester) async {
      await harness.connect(deviceId);
      await pumpDetail(tester);
      holdWritesAfter(10);
      await tapUploadAndSend(tester);

      harness.bluetooth.emitDisconnection(deviceId);
      harness.bluetooth.writeGate!.complete();
      await pumpFrames(tester);

      expect(
        find.textContaining('disconnected during the upload'),
        findsOneWidget,
      );
    });
  });

  testWidgets('fits a 360px wide phone in every upload state', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    proxyCard.startReplies.add(error(DeviceErrorCode.crcMismatch, 0xDEADBEEF));
    await harness.connect(deviceId);
    await pumpDetail(tester);

    await tapUpload(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Send'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('CRC_MISMATCH'), findsOneWidget);
    expect(tester.getRect(find.text('Done')).right, lessThanOrEqualTo(360));

    await tester.tap(find.text('Done'));
    await pumpFrames(tester);
    harness.cooldown.syncFromDevice(deviceId, const Duration(seconds: 179));
    await tester.pump();
    await tapUpload(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Please wait before uploading'), findsOneWidget);
  });
}
