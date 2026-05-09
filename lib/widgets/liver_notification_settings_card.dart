// lib/widgets/liver_notification_settings_card.dart
// Drop-in settings card for hydration & check-in reminders.
// Embed anywhere — e.g., in the profile screen or liver hub.
// No existing files modified.

import 'package:flutter/material.dart';
import '../services/liver_notification_service.dart';

class LiverNotificationSettingsCard extends StatefulWidget {
  const LiverNotificationSettingsCard({super.key});

  @override
  State<LiverNotificationSettingsCard> createState() =>
      _LiverNotificationSettingsCardState();
}

class _LiverNotificationSettingsCardState
    extends State<LiverNotificationSettingsCard> {
  bool _hydrEnabled = false;
  int _hydrInterval = 2;
  bool _checkinEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hydrEnabled =
        await LiverNotificationService.isHydrationReminderEnabled();
    final hydrInterval =
        await LiverNotificationService.getHydrationReminderInterval();
    if (mounted) {
      setState(() {
        _hydrEnabled = hydrEnabled;
        _hydrInterval = hydrInterval;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2)))));
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🔔 Liver Health Reminders',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Hydration toggle
            SwitchListTile(
              title: const Text('Hydration Reminders'),
              subtitle: Text(
                  _hydrEnabled ? 'Every $_hydrInterval hours (8am–9pm)' : 'Off'),
              value: _hydrEnabled,
              activeColor: Colors.blue.shade600,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) async {
                setState(() => _hydrEnabled = val);
                await LiverNotificationService.setHydrationReminders(
                  enabled: val,
                  intervalHours: _hydrInterval,
                );
              },
            ),

            if (_hydrEnabled) ...[
              const Text('Reminder interval',
                  style:
                      TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Slider(
                value: _hydrInterval.toDouble(),
                min: 1,
                max: 4,
                divisions: 3,
                label: 'Every $_hydrInterval hours',
                activeColor: Colors.blue.shade600,
                onChanged: (v) => setState(() => _hydrInterval = v.round()),
                onChangeEnd: (v) async {
                  await LiverNotificationService.setHydrationReminders(
                    enabled: true,
                    intervalHours: v.round(),
                  );
                },
              ),
            ],

            const Divider(height: 20),

            // Daily check-in toggle
            SwitchListTile(
              title: const Text('Daily Check-in (8pm)'),
              subtitle: const Text('Reminder to log symptoms & supplements'),
              value: _checkinEnabled,
              activeColor: Colors.green.shade700,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) async {
                setState(() => _checkinEnabled = val);
                await LiverNotificationService.setDailyCheckinReminder(
                    enabled: val);
              },
            ),
          ],
        ),
      ),
    );
  }
}