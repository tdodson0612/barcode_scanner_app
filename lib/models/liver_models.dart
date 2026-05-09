// lib/models/liver_models.dart
// All new data models for liver health features.
// Drop this single file into lib/models/ — nothing else changes.

// ============================================================
// HYDRATION
// ============================================================

class HydrationEntry {
  final String? id;
  final String userId;
  final DateTime loggedAt;
  final double cups;
  final String? notes;

  HydrationEntry({
    this.id,
    required this.userId,
    required this.loggedAt,
    required this.cups,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'logged_at': loggedAt.toIso8601String(),
        'cups': cups,
        if (notes != null) 'notes': notes,
      };

  factory HydrationEntry.fromJson(Map<String, dynamic> json) => HydrationEntry(
        id: json['id'] as String?,
        userId: json['user_id'] as String,
        loggedAt: DateTime.parse(json['logged_at'] as String),
        cups: (json['cups'] as num).toDouble(),
        notes: json['notes'] as String?,
      );
}

// ============================================================
// SUPPLEMENT SCHEDULE
// ============================================================

class SupplementSchedule {
  final String? id;
  final String userId;
  final String name;
  final String dose;
  final String timeOfDay; // e.g. "08:00" or "evening"
  final List<String> daysOfWeek; // empty = every day
  final bool isActive;

  SupplementSchedule({
    this.id,
    required this.userId,
    required this.name,
    required this.dose,
    required this.timeOfDay,
    this.daysOfWeek = const [],
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        'dose': dose,
        'time_of_day': timeOfDay,
        'days_of_week': daysOfWeek,
        'is_active': isActive,
        'updated_at': DateTime.now().toIso8601String(),
      };

  factory SupplementSchedule.fromJson(Map<String, dynamic> json) =>
      SupplementSchedule(
        id: json['id'] as String?,
        userId: json['user_id'] as String,
        name: json['name'] as String,
        dose: json['dose'] as String,
        timeOfDay: json['time_of_day'] as String,
        daysOfWeek: json['days_of_week'] != null
            ? List<String>.from(json['days_of_week'] as List)
            : [],
        isActive: json['is_active'] as bool? ?? true,
      );

  SupplementSchedule copyWith({
    String? name,
    String? dose,
    String? timeOfDay,
    List<String>? daysOfWeek,
    bool? isActive,
  }) =>
      SupplementSchedule(
        id: id,
        userId: userId,
        name: name ?? this.name,
        dose: dose ?? this.dose,
        timeOfDay: timeOfDay ?? this.timeOfDay,
        daysOfWeek: daysOfWeek ?? this.daysOfWeek,
        isActive: isActive ?? this.isActive,
      );
}

// ============================================================
// SUPPLEMENT TAKEN LOG
// ============================================================

class SupplementTakenEntry {
  final String? id;
  final String userId;
  final String? scheduleId;
  final String name;
  final String dose;
  final DateTime takenAt;
  final String? notes;

  SupplementTakenEntry({
    this.id,
    required this.userId,
    this.scheduleId,
    required this.name,
    required this.dose,
    required this.takenAt,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        if (scheduleId != null) 'schedule_id': scheduleId,
        'name': name,
        'dose': dose,
        'taken_at': takenAt.toIso8601String(),
        if (notes != null) 'notes': notes,
      };

  factory SupplementTakenEntry.fromJson(Map<String, dynamic> json) =>
      SupplementTakenEntry(
        id: json['id'] as String?,
        userId: json['user_id'] as String,
        scheduleId: json['schedule_id'] as String?,
        name: json['name'] as String,
        dose: json['dose'] as String,
        takenAt: DateTime.parse(json['taken_at'] as String),
        notes: json['notes'] as String?,
      );
}

// ============================================================
// SYMPTOM LOG
// ============================================================

enum SymptomType {
  fatigue,
  digestion,
  nausea,
  pain,
  bloating,
  other;

  String get displayName => switch (this) {
        fatigue => 'Fatigue',
        digestion => 'Digestion',
        nausea => 'Nausea',
        pain => 'Pain',
        bloating => 'Bloating',
        other => 'Other',
      };

  String get emoji => switch (this) {
        fatigue => '😴',
        digestion => '🫁',
        nausea => '🤢',
        pain => '😣',
        bloating => '🫃',
        other => '📝',
      };

  static SymptomType fromString(String value) =>
      SymptomType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => SymptomType.other,
      );
}

class SymptomEntry {
  final String? id;
  final String userId;
  final DateTime loggedAt;
  final SymptomType symptomType;
  final int severity; // 1–5
  final String? notes;

  SymptomEntry({
    this.id,
    required this.userId,
    required this.loggedAt,
    required this.symptomType,
    required this.severity,
    this.notes,
  }) : assert(severity >= 1 && severity <= 5);

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'logged_at': loggedAt.toIso8601String(),
        'symptom_type': symptomType.name,
        'severity': severity,
        if (notes != null) 'notes': notes,
      };

  factory SymptomEntry.fromJson(Map<String, dynamic> json) => SymptomEntry(
        id: json['id'] as String?,
        userId: json['user_id'] as String,
        loggedAt: DateTime.parse(json['logged_at'] as String),
        symptomType: SymptomType.fromString(json['symptom_type'] as String),
        severity: json['severity'] as int,
        notes: json['notes'] as String?,
      );
}

// ============================================================
// WEEKLY GOALS
// ============================================================

class LiverWeeklyGoal {
  final String? id;
  final String userId;
  final DateTime weekStartDate;
  final double? goalProteinG;
  final double? goalSodiumMg;
  final double? goalSugarG;
  final double? goalFatG;
  final double? goalFiberG;
  final double? goalWaterCups;
  final int? goalSupplementDays;
  final String? notes;

  LiverWeeklyGoal({
    this.id,
    required this.userId,
    required this.weekStartDate,
    this.goalProteinG,
    this.goalSodiumMg,
    this.goalSugarG,
    this.goalFatG,
    this.goalFiberG,
    this.goalWaterCups,
    this.goalSupplementDays,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'week_start_date': weekStartDate.toIso8601String().split('T').first,
        if (goalProteinG != null) 'goal_protein_g': goalProteinG,
        if (goalSodiumMg != null) 'goal_sodium_mg': goalSodiumMg,
        if (goalSugarG != null) 'goal_sugar_g': goalSugarG,
        if (goalFatG != null) 'goal_fat_g': goalFatG,
        if (goalFiberG != null) 'goal_fiber_g': goalFiberG,
        if (goalWaterCups != null) 'goal_water_cups': goalWaterCups,
        if (goalSupplementDays != null)
          'goal_supplement_days': goalSupplementDays,
        if (notes != null) 'notes': notes,
        'updated_at': DateTime.now().toIso8601String(),
      };

  factory LiverWeeklyGoal.fromJson(Map<String, dynamic> json) =>
      LiverWeeklyGoal(
        id: json['id'] as String?,
        userId: json['user_id'] as String,
        weekStartDate: DateTime.parse(json['week_start_date'] as String),
        goalProteinG: (json['goal_protein_g'] as num?)?.toDouble(),
        goalSodiumMg: (json['goal_sodium_mg'] as num?)?.toDouble(),
        goalSugarG: (json['goal_sugar_g'] as num?)?.toDouble(),
        goalFatG: (json['goal_fat_g'] as num?)?.toDouble(),
        goalFiberG: (json['goal_fiber_g'] as num?)?.toDouble(),
        goalWaterCups: (json['goal_water_cups'] as num?)?.toDouble(),
        goalSupplementDays: json['goal_supplement_days'] as int?,
        notes: json['notes'] as String?,
      );
}

// ============================================================
// NUTRIENT DAILY SNAPSHOT
// ============================================================

class LiverNutrientSnapshot {
  final String? id;
  final String userId;
  final DateTime snapshotDate;
  final double? calories;
  final double? proteinG;
  final double? fatG;
  final double? saturatedFatG;
  final double? sugarG;
  final double? sodiumMg;
  final double? fiberG;
  final double? waterCups;
  final int? dailyScore;
  final double? weightKg;
  final int? supplementCount;

  LiverNutrientSnapshot({
    this.id,
    required this.userId,
    required this.snapshotDate,
    this.calories,
    this.proteinG,
    this.fatG,
    this.saturatedFatG,
    this.sugarG,
    this.sodiumMg,
    this.fiberG,
    this.waterCups,
    this.dailyScore,
    this.weightKg,
    this.supplementCount,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'snapshot_date': snapshotDate.toIso8601String().split('T').first,
        if (calories != null) 'calories': calories,
        if (proteinG != null) 'protein_g': proteinG,
        if (fatG != null) 'fat_g': fatG,
        if (saturatedFatG != null) 'saturated_fat_g': saturatedFatG,
        if (sugarG != null) 'sugar_g': sugarG,
        if (sodiumMg != null) 'sodium_mg': sodiumMg,
        if (fiberG != null) 'fiber_g': fiberG,
        if (waterCups != null) 'water_cups': waterCups,
        if (dailyScore != null) 'daily_score': dailyScore,
        if (weightKg != null) 'weight_kg': weightKg,
        if (supplementCount != null) 'supplement_count': supplementCount,
        'updated_at': DateTime.now().toIso8601String(),
      };

  factory LiverNutrientSnapshot.fromJson(Map<String, dynamic> json) =>
      LiverNutrientSnapshot(
        id: json['id'] as String?,
        userId: json['user_id'] as String,
        snapshotDate: DateTime.parse(json['snapshot_date'] as String),
        calories: (json['calories'] as num?)?.toDouble(),
        proteinG: (json['protein_g'] as num?)?.toDouble(),
        fatG: (json['fat_g'] as num?)?.toDouble(),
        saturatedFatG: (json['saturated_fat_g'] as num?)?.toDouble(),
        sugarG: (json['sugar_g'] as num?)?.toDouble(),
        sodiumMg: (json['sodium_mg'] as num?)?.toDouble(),
        fiberG: (json['fiber_g'] as num?)?.toDouble(),
        waterCups: (json['water_cups'] as num?)?.toDouble(),
        dailyScore: json['daily_score'] as int?,
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        supplementCount: json['supplement_count'] as int?,
      );
}