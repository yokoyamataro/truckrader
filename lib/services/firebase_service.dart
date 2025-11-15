import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vehicle_location.dart';
import '../models/point.dart';
import '../config/app_config.dart';

/// Firebaseとの連携を管理するサービス
class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// シングルトンパターン
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  /// 匿名認証（簡易実装）
  Future<void> signInAnonymously() async {
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
    } catch (e) {
      throw Exception('Firebase認証エラー: $e');
    }
  }

  /// 車両位置情報をFirestoreに送信
  Future<void> uploadVehicleLocation(VehicleLocation location) async {
    try {
      await _firestore
          .collection(AppConfig.firestoreVehiclesCollection)
          .doc(location.vehicleId)
          .set(location.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      throw Exception('位置情報アップロードエラー: $e');
    }
  }

  /// 車両位置情報をFirestoreに送信（リトライ付き）
  Future<void> uploadVehicleLocationWithRetry(VehicleLocation location) async {
    int attempts = 0;
    while (attempts < AppConfig.maxRetryAttempts) {
      try {
        await uploadVehicleLocation(location);
        return; // 成功したら終了
      } catch (e) {
        attempts++;
        if (attempts >= AppConfig.maxRetryAttempts) {
          rethrow; // 最大試行回数に達したらエラーを再スロー
        }
        await Future.delayed(AppConfig.retryDelay);
      }
    }
  }

  /// 車両位置情報のストリームを取得（管理画面用）
  Stream<List<VehicleLocation>> getVehicleLocationsStream() {
    return _firestore
        .collection(AppConfig.firestoreVehiclesCollection)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => VehicleLocation.fromFirestore(doc))
          .toList();
    });
  }

  /// すべての車両位置情報を取得（一度だけ）
  Future<List<VehicleLocation>> getVehicleLocations() async {
    try {
      final snapshot = await _firestore
          .collection('vehicle_locations')
          .get();

      return snapshot.docs
          .map((doc) => VehicleLocation.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('車両位置情報取得エラー: $e');
    }
  }

  /// 特定車両の位置情報を取得
  Future<VehicleLocation?> getVehicleLocation(String vehicleId) async {
    try {
      final doc = await _firestore
          .collection(AppConfig.firestoreVehiclesCollection)
          .doc(vehicleId)
          .get();

      if (doc.exists) {
        return VehicleLocation.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      throw Exception('車両位置情報取得エラー: $e');
    }
  }

  /// ドライバー一覧を取得
  Future<List<Map<String, dynamic>>> getDrivers() async {
    try {
      final snapshot = await _firestore
          .collection('drivers')
          .orderBy('name')
          .get();

      return snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'name': doc['name'] ?? '不明',
          ...doc.data(),
        };
      }).toList();
    } catch (e) {
      throw Exception('ドライバー取得エラー: $e');
    }
  }

  /// 車両一覧を取得
  Future<List<Map<String, dynamic>>> getVehicles() async {
    try {
      final snapshot = await _firestore
          .collection(AppConfig.firestoreVehiclesCollection)
          .orderBy('id')
          .get();

      return snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'vehicleId': doc['vehicleId'] ?? doc.id,
          ...doc.data(),
        };
      }).toList();
    } catch (e) {
      throw Exception('車両取得エラー: $e');
    }
  }

  /// 車両にドライバーを割り当て
  Future<void> assignDriverToVehicle(
    String vehicleId,
    String driverId,
  ) async {
    try {
      await _firestore
          .collection(AppConfig.firestoreVehiclesCollection)
          .doc(vehicleId)
          .update({'driverId': driverId});
    } catch (e) {
      throw Exception('ドライバー割り当てエラー: $e');
    }
  }

  /// 位置情報ログを記録
  Future<void> addLocationLog(VehicleLocation location) async {
    try {
      final logId = '${location.vehicleId}_${location.timestamp.millisecondsSinceEpoch}';

      await _firestore
          .collection('location_logs')
          .doc(logId)
          .set({
        'vehicleId': location.vehicleId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'speed': location.speed,
        'heading': location.heading,
        'accuracy': location.accuracy,
        'status': location.status,
        'timestamp': location.timestamp,
        if (location.driverId != null) 'driverId': location.driverId,
      });
    } catch (e) {
      print('位置情報ログ記録エラー: $e');
      // ログ記録失敗は非致命的エラー
    }
  }

  /// リアルタイム位置情報を vehicle_locations に更新
  Future<void> updateVehicleLocation(VehicleLocation location) async {
    try {
      await _firestore
          .collection('vehicle_locations')
          .doc(location.vehicleId)
          .set(location.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      throw Exception('リアルタイム位置情報更新エラー: $e');
    }
  }

  /// トラッキング状態を更新
  Future<void> updateTrackingStatus(String vehicleId, bool isTracking) async {
    try {
      await _firestore
          .collection('vehicle_locations')
          .doc(vehicleId)
          .set({
            'isTracking': isTracking,
            'trackingStatusUpdatedAt': DateTime.now(),
          }, SetOptions(merge: true));
      print('トラッキング状態を更新: vehicleId=$vehicleId, isTracking=$isTracking');
    } catch (e) {
      print('トラッキング状態更新エラー: $e');
      // 非致命的エラー
    }
  }

  /// 接続状態を確認
  bool get isConnected => _auth.currentUser != null;

  // ==================== ポイント管理 ====================

  /// すべてのポイントを取得（リアルタイム）
  Stream<List<Point>> getPointsStream() {
    return _firestore
        .collection('points')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Point.fromFirestore(doc))
          .toList();
    });
  }

  /// ポイントを追加
  Future<String> addPoint(Point point) async {
    try {
      final docRef = await _firestore
          .collection('points')
          .add(point.toFirestore());
      return docRef.id;
    } catch (e) {
      throw Exception('ポイント追加エラー: $e');
    }
  }

  /// 目的地をvehicle_locationsに設定
  Future<void> setDestination(String vehicleId, String pointId) async {
    try {
      await _firestore
          .collection('vehicle_locations')
          .doc(vehicleId)
          .set({
            'destinationId': pointId,
          }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('目的地設定エラー: $e');
    }
  }

  /// 目的地をクリア
  Future<void> clearDestination(String vehicleId) async {
    try {
      await _firestore
          .collection('vehicle_locations')
          .doc(vehicleId)
          .set({
            'destinationId': FieldValue.delete(),
          }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('目的地クリアエラー: $e');
    }
  }

  /// 車両の目的地IDを取得
  Future<String?> getDestinationId(String vehicleId) async {
    try {
      final doc = await _firestore
          .collection('vehicle_locations')
          .doc(vehicleId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        return data?['destinationId'] as String?;
      }
      return null;
    } catch (e) {
      print('目的地ID取得エラー: $e');
      return null;
    }
  }
}
