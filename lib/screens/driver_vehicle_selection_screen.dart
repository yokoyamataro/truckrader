import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tracking_provider.dart';
import '../services/firebase_service.dart';
import '../models/vehicle_location.dart';

/// ドライバー・車両選択画面
class DriverVehicleSelectionScreen extends StatefulWidget {
  const DriverVehicleSelectionScreen({super.key});

  @override
  State<DriverVehicleSelectionScreen> createState() =>
      _DriverVehicleSelectionScreenState();
}

class _DriverVehicleSelectionScreenState
    extends State<DriverVehicleSelectionScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final drivers = await _firebaseService.getDrivers();
      final vehicles = await _firebaseService.getVehicles();
      final vehicleLocationsList = await _firebaseService.getVehicleLocations();

      // VehicleLocationのリストをマップに変換（vehicleIdをキーとする）
      final vehicleLocations = {
        for (var location in vehicleLocationsList) location.vehicleId: location
      };

      // 車両に location 情報をマージ
      final vehiclesWithStatus = vehicles.map((vehicle) {
        final location = vehicleLocations[vehicle['id']];
        return {
          ...vehicle,
          'location': location,
          'isAvailable': _isVehicleAvailable(location),
        };
      }).toList();

      setState(() {
        _drivers = drivers;
        _vehicles = vehiclesWithStatus;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'データ読み込みエラー: $e';
        _isLoading = false;
      });
    }
  }

  /// 車両が選択可能かどうかを判定（停止中のみ選択可能）
  bool _isVehicleAvailable(VehicleLocation? location) {
    if (location == null) {
      // location データがない場合は選択可能（新規登録時など）
      return true;
    }

    // 完全に停止している場合のみ選択可能
    // "moving" や "idle" は選択不可
    return location.status == 'stopped';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackingProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('ドライバー・車両選択'),
            centerTitle: true,
            backgroundColor: Colors.blue,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _loadData,
                            child: const Text('再試行'),
                          ),
                        ],
                      ),
                    )
                  : SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ドライバー選択
                              _buildSection(
                                title: 'ドライバーを選択',
                                items: _drivers,
                                selectedId: provider.selectedDriverId,
                                onSelected: (driverId) =>
                                    provider.selectDriver(driverId),
                                nameExtractor: (item) => item['name'] ?? '不明',
                              ),
                              const SizedBox(height: 32),

                              // 車両選択
                              _buildSection(
                                title: '車両を選択',
                                items: _vehicles,
                                selectedId: provider.selectedVehicleId,
                                onSelected: (vehicleId) =>
                                    provider.selectVehicle(vehicleId),
                                nameExtractor: (item) =>
                                    item['vehicleId'] ?? item['id'] ?? '不明',
                              ),
                              const SizedBox(height: 32),

                              // 確認ボタン
                              ElevatedButton(
                                onPressed:
                                    (provider.selectedDriverId != null &&
                                            provider.selectedVehicleId != null)
                                        ? () {
                                            Navigator.of(context).pop();
                                          }
                                        : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 20),
                                  disabledBackgroundColor: Colors.grey,
                                ),
                                child: const Text(
                                  '確認',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildSection({
    required String title,
    required List<Map<String, dynamic>> items,
    required String? selectedId,
    required Function(String) onSelected,
    required String Function(Map<String, dynamic>) nameExtractor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Text(
            'データがありません',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              final itemId = item['id'];
              final itemName = nameExtractor(item);
              final isSelected = selectedId == itemId;

              // 車両の場合は選択可否を確認
              final isAvailable = title == '車両を選択'
                  ? (item['isAvailable'] ?? true)
                  : true;

              return Card(
                color: isSelected
                    ? Colors.blue[50]
                    : isAvailable
                        ? null
                        : Colors.grey[100],
                child: ListTile(
                  enabled: isAvailable,
                  selected: isSelected,
                  onTap: isAvailable ? () => onSelected(itemId) : null,
                  leading: Radio<String>(
                    value: itemId,
                    groupValue: selectedId,
                    onChanged: isAvailable ? (value) {
                      if (value != null) {
                        onSelected(value);
                      }
                    } : null,
                  ),
                  title: Text(
                    itemName,
                    style: TextStyle(
                      color: isAvailable ? Colors.black : Colors.grey[500],
                    ),
                  ),
                  subtitle: !isAvailable && title == '車両を選択'
                      ? Text(
                          '走行中のため選択できません',
                          style: TextStyle(
                            color: Colors.red[400],
                            fontSize: 12,
                          ),
                        )
                      : null,
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.blue)
                      : !isAvailable && title == '車両を選択'
                          ? Icon(Icons.lock, color: Colors.grey[500], size: 20)
                          : null,
                ),
              );
            },
          ),
      ],
    );
  }
}
