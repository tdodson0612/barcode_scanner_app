// lib/config/app_config.dart — Fully Updated

class AppConfig {
  // ------------------------------------------------------------
  // SUPABASE (only for authentication — NOT for database reads)
  // ------------------------------------------------------------
  static const String supabaseUrl =
      'https://jmnwyzearnndhlitruyu.supabase.co';

  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imptbnd5emVhcm5uZGhsaXRydXl1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ0MTc4MTMsImV4cCI6MjA2OTk5MzgxM30.i1_79Ew1co2wIsZTyai_t6KucM-fH_NuKBIhqEuY-44';

  // ------------------------------------------------------------
  // CLOUDFLARE WORKER (all DB queries + storage go through this)
  // ------------------------------------------------------------

  // ❗️IMPORTANT: no trailing slash on this line
  static const String cloudflareWorkerUrl =
      'https://shrill-paper-a8ce.terryd0612.workers.dev';

  // Your Worker listens on `/auth`, `/query`, `/query/storage`
  static const String cloudflareWorkerQueryEndpoint =
      'https://shrill-paper-a8ce.terryd0612.workers.dev/query';

  // ------------------------------------------------------------
  // GENERAL APP SETTINGS
  // ------------------------------------------------------------
  static const String appName = 'LiverWise';
  static const bool isProduction = false; // change to true for App Store

  // ------------------------------------------------------------
  // ADS (test ads for now)
  // ------------------------------------------------------------
  static const String androidInterstitialAdId =
      'ca-app-pub-3940256099942544/1033173712';
  static const String iosInterstitialAdId =
      'ca-app-pub-3940256099942544/4411468910';
  static const String androidRewardedAdId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String iosRewardedAdId =
      'ca-app-pub-3940256099942544/1712485313';

  // API settings
  static const String openFoodFactsUrl =
      'https://world.openfoodfacts.org/api/v0/product';
  static const int apiTimeoutSeconds = 15;

  // Feature flags
  static const bool enableDebugPrints = true;
  static const bool enableAds = true;

  // Free scan limit for non-premium users
  static const int freeScanLimit = 3;

  // ------------------------------------------------------------
  // AD HELPERS
  // ------------------------------------------------------------
  static String get interstitialAdId {
    return androidInterstitialAdId; // test IDs work on both
  }

  static String get rewardedAdId {
    return androidRewardedAdId; // test IDs work on both
  }

  // ------------------------------------------------------------
  // DEBUG HELPER
  // ------------------------------------------------------------
  static void debugPrint(String message) {
    if (enableDebugPrints) {
      print('[DEBUG] $message');
    }
  }
}
