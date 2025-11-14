import 'package:cloud_firestore/cloud_firestore.dart';

/// 車両位置情報モデル
class VehicleLocation {
  final String vehicleId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double speed; // km/h
  final double heading; // 方角 0-360度
  final double accuracy; // 精度 メートル
  final String status; // "moving" | "stopped" | "idle"
  final String? driverId; // ドライバーID
  final String? destinationId; // 目的地ID（ポイントID）

  VehicleLocation({
    required this.vehicleId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.speed,
    required this.heading,
    required this.accuracy,
    required this.status,
    this.driverId,
    this.destinationId,
  });

  /// Firestoreドキュメントから生成
  factory VehicleLocation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VehicleLocation(
      vehicleId: doc.id,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      speed: (data['speed'] as num?)?.toDouble() ?? 0.0,
      heading: (data['heading'] as num?)?.toDouble() ?? 0.0,
      accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0.0,
      status: data['status'] as String? ?? 'idle',
      driverId: data['driverId'] as String?,
      destinationId: data['destinationId'] as String?,
    );
  }

  /// Firestoreに保存する形式に変換
  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': Timestamp.fromDate(timestamp),
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
      'status': status,
      if (driverId != null) 'driverId': driverId,
      if (destinationId != null) 'destinationId': destinationId,
    };
  }

  /// コピー作成
  VehicleLocation copyWith({
    String? vehicleId,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    double? speed,
    double? heading,
    double? accuracy,
    String? status,
    String? driverId,
    String? destinationId,
  }) {
    return VehicleLocation(
      vehicleId: vehicleId ?? this.vehicleId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      accuracy: accuracy ?? this.accuracy,
      status: status ?? this.status,
      driverId: driverId ?? this.driverId,
      destinationId: destinationId ?? this.destinationId,
    );
  }
}
