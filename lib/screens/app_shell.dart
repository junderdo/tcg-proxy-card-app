import 'package:flutter/material.dart';

import '../bluetooth/ble_service.dart';
import '../scryfall/scryfall_client.dart';
import 'devices_screen.dart';
import 'home_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.client, required this.bluetooth});

  final ScryfallClient client;
  final BleService bluetooth;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _devicesTab = 1;

  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTab,
        children: [
          HomeScreen(client: widget.client),
          // Built only while visible so leaving the tab stops scanning and
          // disconnects, and Bluetooth isn't touched until the user asks.
          if (_selectedTab == _devicesTab)
            DevicesScreen(bluetooth: widget.bluetooth)
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (tab) => setState(() => _selectedTab = tab),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: 'Cards',
          ),
          NavigationDestination(
            icon: Icon(Icons.bluetooth),
            selectedIcon: Icon(Icons.bluetooth_connected),
            label: 'Devices',
          ),
        ],
      ),
    );
  }
}
