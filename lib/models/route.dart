import 'package:google_maps_flutter/google_maps_flutter.dart';

/// ルート情報モデル
class RouteInfo {
  final List<LatLng> points;  // ルート上の座標リスト
  final int distanceMeters;   // 距離（メートル）
  final int durationSeconds;  // 予想所要時間（秒）
  final String distanceText;  // 距離（表示用テキスト）
  final String durationText;  // 所要時間（表示用テキスト）
  final List<RouteStep> steps; // ルートの詳細ステップ

  RouteInfo({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.distanceText,
    required this.durationText,
    required this.steps,
  });

  /// Google Directions API のレスポンスから生成
  factory RouteInfo.fromDirectionsResponse(Map<String, dynamic> route) {
    final leg = route['legs'][0];
    final distance = leg['distance'];
    final duration = leg['duration'];

    final steps = (leg['steps'] as List)
        .map((step) => RouteStep.fromJson(step))
        .toList();

    // ポリラインをデコード
    final encodedPolyline = route['overview_polyline']['points'];
    final points = _decodePolyline(encodedPolyline);

    return RouteInfo(
      points: points,
      distanceMeters: distance['value'],
      durationSeconds: duration['value'],
      distanceText: distance['text'],
      durationText: duration['text'],
      steps: steps,
    );
  }

  /// ポリラインをデコード（Google Maps API の圧縮ポリラインを座標リストに変換）
  static List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return poly;
  }
}

/// ルートステップ（ターン単位の詳細情報）
class RouteStep {
  final String instruction;     // 指示内容（例：「左折」）
  final int distanceMeters;     // このステップの距離
  final int durationSeconds;    // このステップの所要時間
  final String distanceText;    // 距離（表示用）
  final String durationText;    // 所要時間（表示用）

  RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.distanceText,
    required this.durationText,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final distance = json['distance'];
    final duration = json['duration'];

    return RouteStep(
      instruction: _cleanHtmlTags(json['html_instructions'] ?? ''),
      distanceMeters: distance['value'],
      durationSeconds: duration['value'],
      distanceText: distance['text'],
      durationText: duration['text'],
    );
  }

  /// HTML タグを削除（Google API のレスポンスには HTML タグが含まれる）
  static String _cleanHtmlTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}
