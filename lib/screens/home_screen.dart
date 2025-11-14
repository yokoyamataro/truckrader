import 'package:flutter/material.dart';
import 'driver_vehicle_selection_screen.dart';
import 'map_screen.dart';

/// メイン画面（地図画面のみ）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Tracker'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      const DriverVehicleSelectionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: const MapScreen(),
    );
  }
}
