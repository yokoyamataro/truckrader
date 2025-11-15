import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../providers/tracking_provider.dart';
import '../services/location_service.dart';
import '../models/point.dart';

/// Google Maps を表示する画面
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};  // ルート表示用
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // 1秒ごとに画面を強制更新
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMarker();
  }

  // 方位に応じた車マークを返す
  String _getVehicleIcon(double heading) {
    // heading: 0-360度
    // 0° = 北（↑）, 90° = 東（→）, 180° = 南（↓）, 270° = 西（←）
    if (heading < 45 || heading >= 315) {
      return '🚗'; // 北向き（そのまま表示）
    } else if (heading < 135) {
      return '🚙'; // 東向き
    } else if (heading < 225) {
      return '🚗'; // 南向き
    } else {
      return '🚙'; // 西向き
    }
  }

  void _updateMarker() {
    final provider = Provider.of<TrackingProvider>(context, listen: false);
    final position = provider.currentPosition;
    final points = provider.points;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TrackingProvider>(
      builder: (context, provider, child) {
        // LocationService から直接最新位置を取得（リアルタイム更新）
        final locationService = LocationService();
        final position = locationService.lastPosition ?? provider.currentPosition;

        if (position == null) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final isWeb = kIsWeb;
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;

        // Web版：左右分割、スマホ版：上下分割
        if (isWeb && screenWidth > 600) {
          // Web版：左に地図（50%）、右に状態パネル（50%）
          return Row(
            children: [
              // 左側：地図
              Expanded(
                flex: 1,
                child: _buildMapWidget(position),
              ),
              // 右側：状態パネル
              Expanded(
                flex: 1,
                child: _buildStatusPanel(context, provider, position),
              ),
            ],
          );
        } else {
          // スマホ版：上に地図（50%）、下に状態パネル（50%）
          return Column(
            children: [
              // 上側：地図
              Expanded(
                flex: 1,
                child: _buildMapWidget(position),
              ),
              // 下側：状態パネル
              Expanded(
                flex: 1,
                child: _buildStatusPanel(context, provider, position),
              ),
            ],
          );
        }
      },
    );
  }

  /// 地図ウィジェット
  Widget _buildMapWidget(Position position) {
    return Stack(
      children: [
        Consumer<TrackingProvider>(
          builder: (context, provider, child) {
            // ルート情報が更新されたらポリラインを更新
            _updatePolylines(provider);

            return GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                _updateMarker();
              },
              initialCameraPosition: CameraPosition(
                target: LatLng(position.latitude, position.longitude),
                zoom: 15.0,
              ),
              markers: _markers,
              polylines: _polylines,  // ルートを表示
              myLocationEnabled: kIsWeb ? false : true,
              myLocationButtonEnabled: kIsWeb ? false : true,
              zoomControlsEnabled: true,
              mapType: MapType.normal,
            );
          },
        ),
      ],
    );
  }

  /// ポリラインを更新（ルート情報から）
  void _updatePolylines(TrackingProvider provider) {
    _polylines.clear();

    if (provider.currentRoute != null) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: provider.currentRoute!.points,
          color: Colors.blue,
          width: 5,
          geodesic: true,
        ),
      );
    }
  }

  /// 状態パネル
  Widget _buildStatusPanel(BuildContext context, TrackingProvider provider, Position position) {
    // 最新の位置情報を取得（リアルタイム更新）
    final locationService = LocationService();
    final currentPosition = locationService.lastPosition ?? position;
    final speed = currentPosition.speed * 3.6; // m/s -> km/h
    final isTracking = provider.isTracking;

    return Container(
      color: Colors.grey[100],
      child: Column(
        children: [
          // ヘッダー
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(0),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Text(
                  '車両情報',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // スクロール可能な情報パネル
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 車両ID
                  _buildInfoRow(
                    icon: Icons.local_shipping,
                    label: '車両ID',
                    value: provider.selectedVehicleId ?? 'セットなし',
                  ),
                  const SizedBox(height: 12),

                  // ドライバー名
                  _buildInfoRow(
                    icon: Icons.person,
                    label: 'ドライバー',
                    value: provider.selectedDriverName,
                  ),
                  const SizedBox(height: 12),

                  // トラッキング状態
                  _buildInfoRow(
                    icon: isTracking ? Icons.check_circle : Icons.pause_circle,
                    label: 'トラッキング',
                    value: isTracking ? 'ON' : 'OFF',
                    valueColor: isTracking ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 12),

                  // 速度
                  _buildInfoRow(
                    icon: Icons.speed,
                    label: '速度',
                    value: '${speed.toStringAsFixed(1)} km/h',
                  ),
                  const SizedBox(height: 12),

                  // 位置情報
                  _buildInfoRow(
                    icon: Icons.location_on,
                    label: '緯度',
                    value: currentPosition.latitude.toStringAsFixed(6),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    icon: Icons.location_on,
                    label: '経度',
                    value: currentPosition.longitude.toStringAsFixed(6),
                  ),
                  const SizedBox(height: 16),

                  // 行き先選択
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '行き先',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (provider.points.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            border: Border.all(color: Colors.amber[200]!, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning, color: Colors.amber[700], size: 20),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'ポイントがまだ登録されていません',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        DropdownButton<String>(
                          value: provider.selectedDestinationId,
                          isExpanded: true,
                          hint: const Text('ポイントを選択してください'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('選択なし'),
                            ),
                            ...provider.points.map((point) {
                              return DropdownMenuItem<String>(
                                value: point.id,
                                child: Text(point.name),
                              );
                            }).toList(),
                          ],
                          onChanged: (String? newValue) async {
                            if (newValue != null) {
                              try {
                                // 行き先を設定
                                await provider.setDestination(newValue);

                                // 選択されたポイントを取得
                                final selectedPoint = provider.points
                                    .firstWhere((p) => p.id == newValue);

                                // ルートを計算
                                await provider.calculateRoute(selectedPoint);

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('行き先を設定しました')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('エラー: $e')),
                                );
                              }
                            } else {
                              try {
                                // 行き先をクリア
                                await provider.clearDestination();
                                // ルートをクリア
                                provider.clearRoute();

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('行き先をクリアしました')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('エラー: $e')),
                                );
                              }
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ルート情報表示
                  if (provider.isCalculatingRoute)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.blue[600]),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'ルート計算中...',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (provider.currentRoute != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        border: Border.all(color: Colors.green[200]!, width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.directions_car, color: Colors.green[600], size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'ルート情報',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[600],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.straighten, color: Colors.green[600], size: 16),
                              const SizedBox(width: 8),
                              Text(
                                '距離: ${provider.currentRoute!.distanceText}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.schedule, color: Colors.green[600], size: 16),
                              const SizedBox(width: 8),
                              Text(
                                '所要時間: ${provider.currentRoute!.durationText}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // メッセージ表示エリア（将来実装）
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      border: Border.all(color: Colors.blue[200]!, width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.message, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'メッセージ表示エリア',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // トラッキングボタン
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // トラッキング開始ボタン（▶）
                if (!provider.isTracking)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (provider.selectedDriverId != null &&
                              provider.selectedVehicleId != null)
                          ? () async {
                              await provider.startTracking();
                            }
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('開始'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.grey[300],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                // トラッキング停止ボタン（◼）
                if (provider.isTracking)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await provider.stopTracking();
                      },
                      icon: const Icon(Icons.stop),
                      label: const Text('停止'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 情報行ウィジェット
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebMapView(Position position) {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on, size: 48, color: Colors.blue),
            const SizedBox(height: 16),
            Text(
              '現在位置',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '緯度: ${position.latitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              '経度: ${position.longitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final url = 'https://www.google.com/maps/@${position.latitude},${position.longitude},15z';
                // Web環境でのURL開き処理はここに実装
                print('Map URL: $url');
              },
              child: const Text('Google Maps で開く'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}
