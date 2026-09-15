import 'package:flutter/material.dart';

import '../bluetooth/ble_devices_controller.dart';
import '../bluetooth/ble_service.dart';
import '../scryfall/scryfall_client.dart';
import '../upload/card_uploader.dart';
import '../upload/panel_cooldown.dart';
import 'card_detail_screen.dart';
import 'devices_screen.dart';
import 'home_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.client,
    required this.bluetooth,
    this.uploadEnvironment = const UploadEnvironment(),
  });

  final ScryfallClient client;
  final BleService bluetooth;
  final UploadEnvironment uploadEnvironment;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _devicesTab = 1;

  // Owned here so connections outlive the Devices tab. Creating them doesn't
  // touch Bluetooth; that waits for the Devices tab or an upload.
  late final _devices = BleDevicesController(widget.bluetooth);
  late final _cooldown = PanelCooldown(
    widget.uploadEnvironment.cooldownStore,
    clock: widget.uploadEnvironment.clock,
  );
  late final _uploader = CardUploader(
    bluetooth: widget.bluetooth,
    devices: _devices,
    cooldown: _cooldown,
    environment: widget.uploadEnvironment,
  );

  int _selectedTab = 0;

  @override
  void dispose() {
    _devices.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  void _selectTab(int tab) {
    if (tab == _selectedTab) return;
    if (_selectedTab == _devicesTab) _devices.stopScan();
    setState(() => _selectedTab = tab);
  }

  void _showDevices() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _selectTab(_devicesTab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTab,
        children: [
          HomeScreen(
            client: widget.client,
            buildCardDetail: (card) => CardDetailScreen(
              card: card,
              uploader: _uploader,
              onShowDevices: _showDevices,
            ),
          ),
          // Built only while selected so opening the app doesn't touch
          // Bluetooth.
          if (_selectedTab == _devicesTab)
            DevicesScreen(devices: _devices)
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
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
