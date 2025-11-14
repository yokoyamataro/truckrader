import 'dart:convert';
import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/route.dart';
import '../config/app_config.dart';

/// Google Maps Directions API を使用したルート検索サービス
class RouteService {
  static const String _directionsApi =
    'https://maps.googleapis.com/maps/api/directions/json';

  /// ルートを検索
  /// [origin] 出発地点
  /// [destination] 目的地
  /// 戻り値: RouteInfo またはエラーメッセージ
  Future<RouteInfo?> getRoute(LatLng origin, LatLng destination) async {
    try {
      final url = '$_directionsApi'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=${AppConfig.googleMapsApiKey}'
        '&language=${AppConfig.routeLanguage}'
        '&mode=driving';

      print('ルート検索リクエスト: $url');

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('ルート検索タイムアウト');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP エラー: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        final status = json['status'];
        throw Exception('Google Maps API エラー: $status');
      }

      if ((json['routes'] as List).isEmpty) {
        throw Exception('ルートが見つかりません');
      }

      final route = json['routes'][0] as Map<String, dynamic>;
      final routeInfo = RouteInfo.fromDirectionsResponse(route);

      print('ルート検索成功: ${routeInfo.distanceText}, ${routeInfo.durationText}');

      return routeInfo;
    } catch (e) {
      print('ルート検索エラー: $e');
      return null;
    }
  }

  /// 複数の代替ルートを取得（alternatives=true）
  Future<List<RouteInfo>> getAlternativeRoutes(
    LatLng origin,
    LatLng destination,
  ) async {
    try {
      final url = '$_directionsApi'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=${AppConfig.googleMapsApiKey}'
        '&language=${AppConfig.routeLanguage}'
        '&mode=driving'
        '&alternatives=true';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP エラー: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        throw Exception('Google Maps API エラー: ${json['status']}');
      }

      final routes = json['routes'] as List;
      return routes
          .map((route) => RouteInfo.fromDirectionsResponse(route))
          .toList();
    } catch (e) {
      print('代替ルート検索エラー: $e');
      return [];
    }
  }

  /// 移動時間を推定（リアルタイムトラフィック考慮、有料プランが必要）
  Future<RouteInfo?> getRouteWithTraffic(
    LatLng origin,
    LatLng destination,
  ) async {
    try {
      final now = DateTime.now();
      final url = '$_directionsApi'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&key=${AppConfig.googleMapsApiKey}'
        '&language=${AppConfig.routeLanguage}'
        '&mode=driving'
        '&departure_time=${(now.millisecondsSinceEpoch ~/ 1000)}'
        '&traffic_model=best_guess';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP エラー: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        throw Exception('Google Maps API エラー: ${json['status']}');
      }

      if ((json['routes'] as List).isEmpty) {
        throw Exception('ルートが見つかりません');
      }

      final route = json['routes'][0] as Map<String, dynamic>;
      return RouteInfo.fromDirectionsResponse(route);
    } catch (e) {
      print('トラフィック考慮ルート検索エラー: $e');
      return null;
    }
  }

  /// 直線距離を計算（ハバーサイン公式）
  double calculateHaversineDistance(LatLng origin, LatLng destination) {
    const R = 6371000; // 地球の半径（メートル）
    final phi1 = _toRadians(origin.latitude);
    final phi2 = _toRadians(destination.latitude);
    final deltaLat = _toRadians(destination.latitude - origin.latitude);
    final deltaLng = _toRadians(destination.longitude - origin.longitude);

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(phi1) * math.cos(phi2) *
        math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final distance = R * c;

    return distance;
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }
}
