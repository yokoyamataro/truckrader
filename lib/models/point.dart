import 'package:cloud_firestore/cloud_firestore.dart';

/// ポイント（目的地・配送先）を表すモデル
class Point {
  final String id;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Point({
    required this.id,
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.updatedAt,
  });

  /// Firestoreドキュメントからインスタンスを作成
  factory Point.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Point(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      latitude: (data['latitude'] ?? 0).toDouble(),
      longitude: (data['longitude'] ?? 0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Firestore用のマップに変換
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt ?? DateTime.now()),
    };
  }

  /// このインスタンスのコピーを作成（変更可能）
  Point copyWith({
    String? id,
    String? name,
    String? description,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Point(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() =>
      'Point(id: $id, name: $name, lat: $latitude, lng: $longitude)';
}
