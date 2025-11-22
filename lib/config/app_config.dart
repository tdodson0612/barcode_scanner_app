// lib/config/app_config.dart — Fully Updated

class AppConfig {
  // ------------------------------------------------------------
  // SUPABASE (Auth Only)
  // ------------------------------------------------------------
  static const String supabaseUrl =
      'https://jmnwyzearnndhlitruyu.supabase.co';

  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imptbnd5emVhcm5uZGhsaXRydXl1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ0MTc4MTMsImV4cCI6MjA2OTk5MzgxM30.i1_79Ew1co2wIsZTyai_t6KucM-fH_NuKBIhqEuY-44';

  // ------------------------------------------------------------
  // CLOUDFLARE WORKER (Database + Storage via Worker API)
  // ------------------------------------------------------------

  // Base Worker URL — NO trailing slash
  static const String cloudflareWorkerUrl =
      'https://shrill-paper-a8ce.terryd0612.workers.dev';

  // Query endpoint
  static const String cloudflareWorkerQueryEndpoint =
      'https://shrill-paper-a8ce.terryd0612.workers.dev/query';

  // Storage endpoint (your worker handles this)
  static const String cloudflareWorkerStorageEndpoint =
      'https://shrill-paper-a8ce.terryd0612.workers.dev/storage';

  // ------------------------------------------------------------
  // GENERAL APP SETTINGS
  // ------------------------------------------------------------
  static const String appName = 'LiverWise';
  static const bool isProduction = false; // set true for App Store build

  // ------------------------------------------------------------
  // ADS (test mode)
  // ------------------------------------------------------------
  static const String androidInterstitialAdId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String iosInterstitialAdId =
      'ca-app-pub-3940256099942544/4411468910';

  static const String androidRewardedAdId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String iosRewardedAdId =
      'ca-app-pub-3940256099942544/1712485313';

  // ------------------------------------------------------------
  // API SETTINGS
  // ------------------------------------------------------------
  static const String openFoodFactsUrl =
      'https://world.openfoodfacts.org/api/v0/product';
  static const int apiTimeoutSeconds = 15;

  // ------------------------------------------------------------
  // FEATURE FLAGS
  // ------------------------------------------------------------
  static const bool enableDebugPrints = true;
  static const bool enableAds = true;
  static const int freeScanLimit = 3;

  // ------------------------------------------------------------
  // AD HELPERS
  // ------------------------------------------------------------
  static String get interstitialAdId => androidInterstitialAdId;
  static String get rewardedAdId => androidRewardedAdId;

  // ------------------------------------------------------------
  // DEBUG HELPER
  // ------------------------------------------------------------
  static void debugPrint(String message) {
    if (enableDebugPrints) {
      // ignore: avoid_print
      print('[DEBUG] $message');
    }
  }
}
