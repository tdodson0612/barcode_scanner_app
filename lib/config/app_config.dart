// lib/config/app_config.dart - Updated with Cloudflare Worker configuration
class AppConfig {
  // Supabase credentials (kept for auth and other non-egress operations)
  static const String supabaseUrl = 'https://jmnwyzearnndhlitruyu.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imptbnd5emVhcm5uZGhsaXRydXl1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ0MTc4MTMsImV4cCI6MjA2OTk5MzgxM30.i1_79Ew1co2wIsZTyai_t6KucM-fH_NuKBIhqEuY-44';
  
  // Cloudflare Worker configuration (for zero-egress data operations)
  // ALL database reads/writes and storage downloads go through this Worker
  static const String cloudflareWorkerUrl = 'https://shrill-paper-a8ce.terryd0612.workers.dev';
  static const String cloudflareWorkerQueryEndpoint = '$cloudflareWorkerUrl/query';
  
  // NOTE: Cloudflare API token is NOT included here for security
  // The Worker handles authentication internally - Flutter only calls the Worker URL
  
  // App settings
  static const String appName = 'LiverWise';
  static const bool isProduction = false; // Set to true when you publish to app store
  
  // Ad Unit IDs
  // For testing/development - these are Google's test ad IDs (they're safe to use)
  static const String androidInterstitialAdId = 'ca-app-pub-3940256099942544/1033173712';
  static const String iosInterstitialAdId = 'ca-app-pub-3940256099942544/4411468910';
  static const String androidRewardedAdId = 'ca-app-pub-3940256099942544/5224354917';
  static const String iosRewardedAdId = 'ca-app-pub-3940256099942544/1712485313';
  
  // When you get real AdMob IDs later, replace the test IDs above with:
  // static const String androidInterstitialAdId = 'ca-app-pub-YOUR-REAL-ID/1234567890';
  
  // API settings
  static const String openFoodFactsUrl = 'https://world.openfoodfacts.org/api/v0/product';
  static const int apiTimeoutSeconds = 15;
  
  // Feature flags
  static const bool enableDebugPrints = true; // Set to false for app store
  static const bool enableAds = true;
  static const int freeScanLimit = 3;
  
  // Helper methods to get the right ad ID for the current platform
  static String get interstitialAdId {
    if (isProduction) {
      // TODO: Replace with your real production ad IDs when you get them
      return androidInterstitialAdId;
    }
    // Use test IDs during development
    return androidInterstitialAdId; // This will work on both Android and iOS for testing
  }
  
  static String get rewardedAdId {
    if (isProduction) {
      // TODO: Replace with your real production ad IDs when you get them
      return androidRewardedAdId;
    }
    // Use test IDs during development
    return androidRewardedAdId; // This will work on both Android and iOS for testing
  }
  
  // Helper method to print debug messages only when enabled
  static void debugPrint(String message) {
    if (enableDebugPrints) {
      print('[DEBUG] $message');
    }
  }
}