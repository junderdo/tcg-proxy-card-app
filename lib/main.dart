import 'package:flutter/material.dart';

import 'bluetooth/ble_service.dart';
import 'bluetooth/flutter_blue_plus_service.dart';
import 'screens/app_shell.dart';
import 'scryfall/scryfall_client.dart';

void main() {
  runApp(
    TcgProxyCardApp(
      client: ScryfallClient(),
      bluetooth: FlutterBluePlusService(),
    ),
  );
}

class TcgProxyCardApp extends StatelessWidget {
  const TcgProxyCardApp({
    super.key,
    required this.client,
    required this.bluetooth,
  });

  final ScryfallClient client;
  final BleService bluetooth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TCG Proxy Cards',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: AppShell(client: client, bluetooth: bluetooth),
    );
  }
}
