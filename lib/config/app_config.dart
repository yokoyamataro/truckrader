/// アプリケーション設定
class AppConfig {
  // 車両ID（実運用時はFirebase Authenticationや設定画面から取得）
  static const String vehicleId = 'TRUCK-001';

  // 位置情報更新間隔
  static const Duration locationUpdateIntervalMoving = Duration(seconds: 10);
  static const Duration locationUpdateIntervalStopped = Duration(minutes: 1);

  // 移動判定の最小距離（メートル）
  static const double minDistanceFilter = 100.0;

  // 停車中と判定する速度（km/h）
  static const double stoppedSpeedThreshold = 5.0;

  // バックグラウンドタスク設定
  static const String backgroundTaskName = 'vehicleLocationTracking';
  static const Duration backgroundTaskInterval = Duration(minutes: 15);

  // Firebase設定（実際のFirebaseプロジェクト作成後に設定）
  static const String firestoreVehiclesCollection = 'vehicles';

  // エラー再試行設定
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 5);

  // Google Maps API キー（環境変数から取得することを推奨）
  // 実装時には環境変数で設定してください
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';

  // ルート検索設定
  static const String routeLanguage = 'ja';  // 日本語でルート情報を取得
}
