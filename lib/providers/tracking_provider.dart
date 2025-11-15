import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../services/firebase_service.dart';
import '../services/route_service.dart';
import '../models/point.dart';
import '../models/route.dart';
import '../models/vehicle_location.dart';

/// トラッキング状態を管理するProvider
class TrackingProvider with ChangeNotifier {
  final LocationService _locationService = LocationService();
  final FirebaseService _firebaseService = FirebaseService();
  final RouteService _routeService = RouteService();

  bool _isTracking = false;
  Position? _currentPosition;
  String _statusMessage = '停止中';
  bool _isFirebaseConnected = false;
  String? _selectedDriverId;
  String? _selectedVehicleId;
  String? _selectedDestinationId;
  List<Map<String, dynamic>> _drivers = [];
  Map<String, String> _driverNameMap = {}; // driverId -> driverName マッピング
  List<Point> _points = [];
  RouteInfo? _currentRoute;  // 現在のルート情報
  bool _isCalculatingRoute = false;  // ルート計算中フラグ
  List<VehicleLocation> _otherVehicles = [];  // 他車両の位置情報

  bool get isTracking => _isTracking;
  Position? get currentPosition => _currentPosition;
  String get statusMessage => _statusMessage;
  bool get isFirebaseConnected => _isFirebaseConnected;
  String? get selectedDriverId => _selectedDriverId;
  String? get selectedVehicleId => _selectedVehicleId;
  String? get selectedDestinationId => _selectedDestinationId;
  List<Point> get points => _points;
  RouteInfo? get currentRoute => _currentRoute;
  bool get isCalculatingRoute => _isCalculatingRoute;
  String get selectedDriverName => _selectedDriverId != null ? (_driverNameMap[_selectedDriverId] ?? _selectedDriverId ?? 'セットなし') : 'セットなし';
  List<VehicleLocation> get otherVehicles => _otherVehicles;

  /// 初期化（SharedPreferences から前回の選択を読み込み）
  /// 位置情報取得も開始
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedDriverId = prefs.getString('selectedDriverId');
      _selectedVehicleId = prefs.getString('selectedVehicleId');

      // Firebase認証
      await _firebaseService.signInAnonymously();
      _isFirebaseConnected = _firebaseService.isConnected;

      // ドライバーデータを取得
      await _loadDrivers();

      // ポイントデータのリスニングを開始
      startListeningToPoints();

      // 他車両の位置情報リスニングを開始
      startListeningToOtherVehicles();

      // 車両の目的地を読み込み
      if (_selectedVehicleId != null) {
        _selectedDestinationId = await _firebaseService.getDestinationId(_selectedVehicleId!);
        // 目的地が設定されている場合、ルートを計算
        if (_selectedDestinationId != null) {
          await _loadAndCalculateRouteToDestination();
        }
      }

      // 位置情報取得を開始（アプリ起動時）
      await _locationService.startFetching();

      // 位置情報の定期更新を開始（UI更新用）
      _startPositionUpdates();

      notifyListeners();
    } catch (e) {
      print('初期化エラー: $e');
    }
  }

  /// ドライバーデータを読み込む
  Future<void> _loadDrivers() async {
    try {
      _drivers = await _firebaseService.getDrivers();
      // ドライバーID -> ドライバー名のマップを作成
      _driverNameMap = {};
      for (final driver in _drivers) {
        _driverNameMap[driver['id']] = driver['name'] ?? '不明';
      }
      print('ドライバーデータ読み込み完了: ${_driverNameMap.length}件');
    } catch (e) {
      print('ドライバーデータ読み込みエラー: $e');
    }
  }

  /// ドライバーを選択
  Future<void> selectDriver(String driverId) async {
    try {
      _selectedDriverId = driverId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedDriverId', driverId);
      notifyListeners();
    } catch (e) {
      print('ドライバー選択エラー: $e');
    }
  }

  /// 車両を選択
  Future<void> selectVehicle(String vehicleId) async {
    try {
      _selectedVehicleId = vehicleId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedVehicleId', vehicleId);
      notifyListeners();
    } catch (e) {
      print('車両選択エラー: $e');
    }
  }

  /// トラッキング開始（データ送信開始）
  Future<void> startTracking() async {
    try {
      _statusMessage = 'トラッキング開始中...';
      notifyListeners();

      // 選択された車両IDをLocationServiceに設定
      if (_selectedVehicleId != null) {
        print('トラッキング開始: 選択された車両ID=$_selectedVehicleId');
        _locationService.setSelectedVehicleId(_selectedVehicleId!);
      } else {
        print('トラッキング開始: 車両IDが選択されていません。デフォルトを使用します');
      }

      // 選択されたドライバーIDをLocationServiceに設定
      if (_selectedDriverId != null) {
        print('トラッキング開始: 選択されたドライバーID=$_selectedDriverId');
        _locationService.setSelectedDriverId(_selectedDriverId!);
      }

      // データ送信開始（位置情報取得は既に開始済み）
      await _locationService.startTracking();

      _isTracking = true;
      _statusMessage = 'トラッキング中';
      notifyListeners();
    } catch (e) {
      _statusMessage = 'エラー: $e';
      _isTracking = false;
      notifyListeners();
    }
  }

  /// トラッキング停止（データ送信停止）
  Future<void> stopTracking() async {
    await _locationService.stopTracking();
    _isTracking = false;
    _statusMessage = '停止中';
    notifyListeners();
  }

  /// 位置情報の定期更新（UI用）
  /// 取得済みの位置情報をUIに反映
  void _startPositionUpdates() {
    print('TrackingProvider: _startPositionUpdates 開始');
    // 定期的に現在位置を更新
    Future.delayed(const Duration(seconds: 1), () async {
      print('TrackingProvider: 定期更新実行 isFetching=${_locationService.isFetching}');
      // 位置情報取得中であれば更新
      if (_locationService.isFetching) {
        final newPosition = _locationService.lastPosition;
        print('TrackingProvider: lastPosition = $newPosition');
        if (newPosition != null) {
          // 位置が変わったかチェック（緯度・経度で比較）
          final positionChanged = _currentPosition == null ||
              _currentPosition!.latitude != newPosition.latitude ||
              _currentPosition!.longitude != newPosition.longitude;

          _currentPosition = newPosition;

          if (positionChanged) {
            print('TrackingProvider: 位置更新 ${_currentPosition?.latitude}, ${_currentPosition?.longitude}');
          }

          // 位置が変わっていなくてもnotifyListeners()を呼ぶ（UIが確実に更新されるように）
          notifyListeners();
        }
      }
      _startPositionUpdates(); // 再帰的に呼び出し
    });
  }

  /// 現在位置を手動更新
  Future<void> refreshPosition() async {
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        _currentPosition = position;
        notifyListeners();
      }
    } catch (e) {
      print('位置情報更新エラー: $e');
    }
  }

  /// ポイントリスニングを開始
  void startListeningToPoints() {
    try {
      _firebaseService.getPointsStream().listen((points) {
        _points = points;
        // ポイントが読み込まれた後、目的地が設定されていればルートを計算
        if (_selectedDestinationId != null && _currentRoute == null && _points.isNotEmpty) {
          _loadAndCalculateRouteToDestination();
        }
        notifyListeners();
      });
    } catch (e) {
      print('ポイントリスニングエラー: $e');
    }
  }

  /// 目的地を設定
  Future<void> setDestination(String pointId) async {
    try {
      if (_selectedVehicleId == null) {
        throw Exception('車両が選択されていません');
      }
      _selectedDestinationId = pointId;
      await _firebaseService.setDestination(_selectedVehicleId!, pointId);
      notifyListeners();
    } catch (e) {
      print('目的地設定エラー: $e');
      rethrow;
    }
  }

  /// 目的地をクリア
  Future<void> clearDestination() async {
    try {
      if (_selectedVehicleId == null) {
        throw Exception('車両が選択されていません');
      }
      _selectedDestinationId = null;
      await _firebaseService.clearDestination(_selectedVehicleId!);
      notifyListeners();
    } catch (e) {
      print('目的地クリアエラー: $e');
      rethrow;
    }
  }

  /// 新しいポイントを追加
  Future<String> addPoint(Point point) async {
    try {
      final pointId = await _firebaseService.addPoint(point);
      return pointId;
    } catch (e) {
      print('ポイント追加エラー: $e');
      rethrow;
    }
  }

  /// ルート情報を計算
  /// [destination] 目的地ポイント
  Future<void> calculateRoute(Point destination) async {
    try {
      if (_currentPosition == null) {
        throw Exception('現在位置が取得されていません');
      }

      _isCalculatingRoute = true;
      notifyListeners();

      final origin = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final dest = LatLng(destination.latitude, destination.longitude);

      print('ルート計算開始: $origin → $dest');

      final route = await _routeService.getRoute(origin, dest);

      if (route != null) {
        _currentRoute = route;
        print('ルート計算成功: ${route.distanceText}, ${route.durationText}');
      } else {
        _currentRoute = null;
        print('ルート計算失敗');
      }

      _isCalculatingRoute = false;
      notifyListeners();
    } catch (e) {
      print('ルート計算エラー: $e');
      _isCalculatingRoute = false;
      _currentRoute = null;
      notifyListeners();
    }
  }

  /// ルート情報をクリア
  void clearRoute() {
    _currentRoute = null;
    notifyListeners();
  }

  /// 目的地IDからポイント情報を取得してルートを計算
  Future<void> _loadAndCalculateRouteToDestination() async {
    try {
      if (_selectedDestinationId == null) return;

      // ポイント一覧から目的地を検索
      final destination = _points.firstWhere(
        (point) => point.id == _selectedDestinationId,
        orElse: () => throw Exception('目的地が見つかりません'),
      );

      // ルートを計算
      await calculateRoute(destination);
    } catch (e) {
      print('目的地ルート計算エラー: $e');
    }
  }

  /// 他車両の位置情報リスニングを開始
  void startListeningToOtherVehicles() {
    try {
      _firebaseService.getVehicleLocationsStream().listen((vehicles) {
        // 自車両以外で、status が "stopped" 以外の車両のみフィルタリング
        _otherVehicles = vehicles.where((vehicle) {
          final isNotSelf = vehicle.vehicleId != _selectedVehicleId;
          final isNotStopped = vehicle.status != 'stopped';
          return isNotSelf && isNotStopped;
        }).toList();

        print('他車両情報更新: ${_otherVehicles.length}台');
        notifyListeners();
      });
    } catch (e) {
      print('他車両リスニングエラー: $e');
    }
  }
}
