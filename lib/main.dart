import 'package:flutter/material.dart';

import 'scryfall/scryfall_client.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(TcgProxyCardApp(client: ScryfallClient()));
}

class TcgProxyCardApp extends StatelessWidget {
  const TcgProxyCardApp({super.key, required this.client});

  final ScryfallClient client;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TCG Proxy Cards',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: HomeScreen(client: client),
    );
  }
}
