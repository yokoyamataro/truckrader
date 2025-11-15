import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/vehicle_location.dart';
import '../config/app_config.dart';
import 'firebase_service.dart';

/// 位置情報取得・追跡サービス
class LocationService {
  final FirebaseService _firebaseService = FirebaseService();
  Timer? _locationFetchTimer; // 位置情報取得用タイマー
  Timer? _locationSendTimer;  // 位置情報送信用タイマー
  Position? _lastPosition;
  bool _isFetching = false;   // 位置情報取得中フラグ
  bool _isTracking = false;   // データ送信中フラグ
  String? _selectedVehicleId;
  String? _selectedDriverId;  // 選択されたドライバーID
  StreamSubscription<Position>? _positionStreamSubscription; // 位置情報ストリーム

  /// シングルトンパターン
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  /// 選択された車両IDを設定
  void setSelectedVehicleId(String vehicleId) {
    _selectedVehicleId = vehicleId;
  }

  /// 選択されたドライバーIDを設定
  void setSelectedDriverId(String driverId) {
    _selectedDriverId = driverId;
  }

  /// 位置情報パーミッションを確認・リクエスト
  Future<bool> requestLocationPermission() async {
    try {
      // パーミッション状態を確認
      PermissionStatus status = await Permission.location.status;

      if (status.isDenied) {
        // パーミッションをリクエスト
        status = await Permission.location.request();
      }

      if (status.isPermanentlyDenied) {
        // 設定画面を開く
        await openAppSettings();
        return false;
      }

      // バックグラウンド位置情報パーミッション（Android のみ）
      try {
        if (await Permission.locationAlways.isDenied) {
          await Permission.locationAlways.request();
        }
      } catch (e) {
        // Web などでサポートされていない場合はスキップ
        print('バックグラウンド位置情報パーミッションはサポートされていません: $e');
      }

      return status.isGranted;
    } catch (e) {
      // Web 環境などでパーミッションがサポートされていない場合
      print('位置情報パーミッション処理エラー（Web環境では無視）: $e');
      return true; // Web では権限関係なく続行
    }
  }

  /// 位置情報サービスが有効か確認
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// 位置情報の取得を開始（アプリ起動時に呼び出し）
  /// トラッキングの有無に関わらず、位置情報をリアルタイムで取得
  Future<void> startFetching() async {
    if (_isFetching) {
      print('既に位置情報取得中です');
      return;
    }

    // パーミッションリクエスト
    try {
      await requestLocationPermission();
    } catch (e) {
      print('パーミッションリクエスト失敗: $e');
    }

    _isFetching = true;
    print('位置情報取得開始（ストリーム監視）');

    // 初回実行（ストリーム開始まで待つ）
    await _fetchLocation();

    // Geolocator のストリームを監視（リアルタイム位置情報更新）
    // distanceFilter を 0 に設定して、常にリアルタイムで更新
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // 0 = フィルターなし、常に更新
      ),
    ).listen(
      (Position position) {
        _lastPosition = position;
        print('位置情報更新（ストリーム）: ${position.latitude}, ${position.longitude}, 速度: ${(position.speed * 3.6).toStringAsFixed(1)}km/h');

        // トラッキング中の場合は即座にFirestoreに送信
        if (_isTracking) {
          print('トラッキング中: 位置情報を即座に送信');
          _sendLocation();
        }
      },
      onError: (e) {
        print('位置情報ストリーム エラー: $e');
      },
    );
  }

  /// 位置情報の取得を停止
  void stopFetching() {
    _isFetching = false;
    _locationFetchTimer?.cancel();
    _locationFetchTimer = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    print('位置情報取得停止（ストリーム監視終了）');
  }

  /// 位置情報のみ取得（Firestoreには送信しない）
  Future<void> _fetchLocation() async {
    try {
      final position = await getCurrentPosition();
      if (position == null) return;

      _lastPosition = position;
      print('位置情報取得: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('位置情報取得エラー: $e');
    }
  }

  /// 現在位置を取得
  Future<Position?> getCurrentPosition() async {
    try {
      // キャッシュされた位置情報ではなく、新しい位置情報を強制的に取得
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        forceAndroidLocationManager: false,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          // タイムアウト時は _lastPosition があればそれを返す
          print('位置情報取得がタイムアウト。_lastPosition を使用します。');
          if (_lastPosition != null) {
            return _lastPosition!;
          }
          // _lastPosition がない場合は例外をスロー（キャッチされて null が返される）
          throw TimeoutException('位置情報取得タイムアウト');
        },
      );
      return position;
    } catch (e) {
      print('位置情報取得エラー: $e');
      // エラー時は _lastPosition があればそれを返す
      return _lastPosition;
    }
  }

  /// トラッキング開始（データ送信開始）
  /// 事前に startFetching() が呼ばれていることを前提とします
  Future<void> startTracking() async {
    if (_isTracking) {
      print('既にトラッキング中です');
      return;
    }

    _isTracking = true;
    print('トラッキング開始（データ送信開始）');
    print('選択された車両ID: $_selectedVehicleId');
    print('位置情報取得中: $_isFetching, 最後の位置: $_lastPosition');

    // Firestoreにトラッキング開始を通知
    if (_selectedVehicleId != null) {
      await _firebaseService.updateTrackingStatus(_selectedVehicleId!, true);
    }

    // 定期的に位置情報をFirestoreに送信（常に最新の位置情報を送信）
    _locationSendTimer = Timer.periodic(
      AppConfig.locationUpdateIntervalMoving,
      (timer) async {
        if (_isTracking) {
          print('定期送信: 位置情報を送信します...');
          await _sendLocation();
        }
      },
    );

    // 初回実行
    await _sendLocation();
  }

  /// トラッキング停止（データ送信停止）
  /// 位置情報の取得は継続します
  Future<void> stopTracking() async {
    _isTracking = false;
    _locationSendTimer?.cancel();
    _locationSendTimer = null;
    print('トラッキング停止（データ送信停止）');

    // Firestoreにトラッキング停止を通知
    if (_selectedVehicleId != null) {
      await _firebaseService.updateTrackingStatus(_selectedVehicleId!, false);
    }
  }

  /// Firestoreに位置情報を送信（トラッキング中のみ実行）
  Future<void> _sendLocation() async {
    try {
      if (_lastPosition == null) {
        print('位置情報がまだ取得されていません');
        return;
      }

      final position = _lastPosition!;

      // ステータス判定
      final speed = position.speed * 3.6; // m/s -> km/h
      final status = speed < AppConfig.stoppedSpeedThreshold ? 'stopped' : 'moving';

      // VehicleLocationオブジェクト作成（選択された車両IDとドライバーIDを使用）
      final vehicleLocation = VehicleLocation(
        vehicleId: _selectedVehicleId ?? AppConfig.vehicleId,
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
        speed: speed,
        heading: position.heading,
        accuracy: position.accuracy,
        status: status,
        driverId: _selectedDriverId,
      );

      print('位置情報送信中... vehicleId=${vehicleLocation.vehicleId}, lat=${position.latitude}, lng=${position.longitude}');

      // Firestoreにアップロード
      // 1. リアルタイム位置情報を vehicle_locations に更新
      await _firebaseService.updateVehicleLocation(vehicleLocation);

      // 2. 位置情報ログを location_logs に記録
      await _firebaseService.addLocationLog(vehicleLocation);

      print('位置情報送信完了: vehicleId=${vehicleLocation.vehicleId}, ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('位置情報送信エラー: $e');
    }
  }

  /// トラッキング状態を取得
  bool get isTracking => _isTracking;

  /// 位置情報取得状態を取得
  bool get isFetching => _isFetching;

  /// 最後の位置情報を取得
  Position? get lastPosition => _lastPosition;
}
