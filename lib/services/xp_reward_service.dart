// xp_reward_service.dart
import 'database_service_core.dart';
import 'xp_service.dart';

class XpRewardService {
  static Future<void> rewardXPFromBadge(int xp, String badgeId) async {
    await XPService.addXP(
      xp,
      reason: 'Badge: $badgeId',
    );
  }
}
