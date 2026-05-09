// lib/pages/liver_hub_page.dart
// Central hub for all liver-health features.
// Accessed from main_navigation.dart as a new bottom-nav tab.
// Route: '/liver-hub'   (also navigates to sub-routes directly)
// No existing files modified.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/tracker_service.dart';
import '../services/liver_features_service.dart';
import '../config/app_config.dart';

class LiverHubPage extends StatefulWidget {
  const LiverHubPage({super.key});

  @override
  State<LiverHubPage> createState() => _LiverHubPageState();
}

class _LiverHubPageState extends State<LiverHubPage> {
  String? _userId;

  // Summary data for the at-a-glance cards
  int? _weeklyScore;
  double _todayCups = 0;
  int _todaySupplements = 0;
  int _symptomCount7d = 0;
  bool _loading = true;

  static const double _dailyWaterGoal = 8.0;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id;
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (_userId == null) return;
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final [weekScore, cups, schedules, takenToday, symptoms] =
          await Future.wait([
        TrackerService.getWeeklyScore(_userId!),
        LiverFeaturesService.getTodayCups(today),
        LiverFeaturesService.getSupplementSchedules(),
        LiverFeaturesService.getSupplementTakenLog(
          from: DateTime.parse(today),
          to: DateTime.parse(today).add(const Duration(days: 1)),
        ),
        LiverFeaturesService.getSymptomLog(
          from: DateTime.now().subtract(const Duration(days: 7)),
        ),
      ]);

      if (mounted) {
        setState(() {
          _weeklyScore = weekScore as int?;
          _todayCups = cups as double;
          _todaySupplements =
              (takenToday as List).length;
          _symptomCount7d = (symptoms as List).length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      AppConfig.debugPrint('Hub load error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liver Health'),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loading = true);
              _loadSummary();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSummary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- At-a-glance row ----
              if (_loading)
                const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()))
              else
                _SummaryRow(
                  weeklyScore: _weeklyScore,
                  todayCups: _todayCups,
                  dailyWaterGoal: _dailyWaterGoal,
                  todaySupplements: _todaySupplements,
                  symptomCount7d: _symptomCount7d,
                ),

              const SizedBox(height: 24),

              // ---- Feature cards ----
              const Text('Track & Monitor',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              _FeatureGrid(
                features: [
                  _FeatureTile(
                    icon: Icons.water_drop_rounded,
                    color: Colors.blue.shade600,
                    title: 'Hydration Log',
                    subtitle: '${_todayCups.toStringAsFixed(1)} / 8 cups today',
                    route: '/hydration-log',
                  ),
                  _FeatureTile(
                    icon: Icons.medication_rounded,
                    color: Colors.green.shade700,
                    title: 'Supplements',
                    subtitle: '$_todaySupplements taken today',
                    route: '/supplement-schedule',
                  ),
                  _FeatureTile(
                    icon: Icons.sick_rounded,
                    color: Colors.orange.shade700,
                    title: 'Symptom Log',
                    subtitle: '$_symptomCount7d logs this week',
                    route: '/symptom-log',
                  ),
                  _FeatureTile(
                    icon: Icons.bar_chart_rounded,
                    color: Colors.purple.shade600,
                    title: 'Dashboard',
                    subtitle: 'Trends & weekly goals',
                    route: '/liver-dashboard',
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ---- Quick tip card ----
              _TipCard(),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Summary row at top
// ----------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  final int? weeklyScore;
  final double todayCups;
  final double dailyWaterGoal;
  final int todaySupplements;
  final int symptomCount7d;

  const _SummaryRow({
    required this.weeklyScore,
    required this.todayCups,
    required this.dailyWaterGoal,
    required this.todaySupplements,
    required this.symptomCount7d,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryCard(
          label: 'Weekly Score',
          value: weeklyScore != null ? '$weeklyScore' : '—',
          unit: weeklyScore != null ? '/100' : '',
          color: Colors.green.shade700,
          icon: Icons.star_rounded,
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          label: "Today's Water",
          value: todayCups.toStringAsFixed(1),
          unit: '/ 8 cups',
          color: Colors.blue.shade600,
          icon: Icons.water_drop_rounded,
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          label: 'Symptoms (7d)',
          value: '$symptomCount7d',
          unit: 'logs',
          color: Colors.orange.shade700,
          icon: Icons.sick_rounded,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ),
            if (unit.isNotEmpty)
              Text(unit,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 10, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------
// Feature grid
// ----------------------------------------------------------------

class _FeatureTile {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;

  _FeatureTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}

class _FeatureGrid extends StatelessWidget {
  final List<_FeatureTile> features;
  const _FeatureGrid({required this.features});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: features.map((f) {
        return InkWell(
          onTap: () => Navigator.pushNamed(context, f.route),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: f.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: f.color.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(f.icon, color: f.color, size: 28),
                const SizedBox(height: 8),
                Text(f.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: f.color)),
                const SizedBox(height: 2),
                Text(f.subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ----------------------------------------------------------------
// Rotating liver-health tip
// ----------------------------------------------------------------

class _TipCard extends StatelessWidget {
  static const List<String> _tips = [
    '🥦 Cruciferous vegetables like broccoli support liver enzyme function.',
    '☕ Studies suggest moderate coffee consumption may reduce liver inflammation.',
    '🚫 Limit alcohol — even small amounts stress liver metabolism.',
    '💧 Staying hydrated helps your liver flush toxins more efficiently.',
    '🥑 Healthy fats from avocado and olive oil support liver cell membranes.',
    '🧄 Garlic activates liver enzymes that help flush out body toxins.',
    '🍋 Citrus fruits help the liver produce detoxifying enzymes.',
    '🧘 Regular exercise reduces liver fat and lowers inflammation.',
  ];

  @override
  Widget build(BuildContext context) {
    final idx = DateTime.now().weekday % _tips.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.shade800,
            Colors.green.shade600,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Text('💡', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Liver Health Tip',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(_tips[idx],
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}