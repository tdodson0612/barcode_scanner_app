// lib/models/alcohol_entry.dart
// Data model for a single alcohol consumption log entry.
// Drop into lib/models/ — nothing existing is modified.

class AlcoholEntry {
  final String? id;
  final String userId;
  final DateTime loggedAt;
  final String drinkName;       // e.g. "Beer", "Wine", "Whiskey"
  final double totalVolumeOz;   // total volume of the drink in oz
  final double abvPercent;      // alcohol by volume, e.g. 5.0 for 5%
  final String? notes;

  AlcoholEntry({
    this.id,
    required this.userId,
    required this.loggedAt,
    required this.drinkName,
    required this.totalVolumeOz,
    required this.abvPercent,
    this.notes,
  });

  // ── Core calculation ──────────────────────────────────────────────────────

  /// Pure alcohol volume in oz  =  total volume × (ABV% / 100)
  double get pureAlcoholOz => totalVolumeOz * (abvPercent / 100);

  /// Standard drinks  (1 standard drink = 0.6 oz pure alcohol in the US)
  double get standardDrinks => pureAlcoholOz / 0.6;

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'logged_at': loggedAt.toIso8601String(),
        'drink_name': drinkName,
        'total_volume_oz': totalVolumeOz,
        'abv_percent': abvPercent,
        if (notes != null) 'notes': notes,
      };

  factory AlcoholEntry.fromJson(Map<String, dynamic> json) => AlcoholEntry(
        id: json['id'] as String?,
        userId: json['user_id'] as String,
        loggedAt: DateTime.parse(json['logged_at'] as String),
        drinkName: json['drink_name'] as String,
        totalVolumeOz: (json['total_volume_oz'] as num).toDouble(),
        abvPercent: (json['abv_percent'] as num).toDouble(),
        notes: json['notes'] as String?,
      );
}

// ── Preset drinks for quick-log ───────────────────────────────────────────

class DrinkPreset {
  final String name;
  final double volumeOz;
  final double abvPercent;
  final String emoji;

  const DrinkPreset({
    required this.name,
    required this.volumeOz,
    required this.abvPercent,
    required this.emoji,
  });

  double get pureAlcoholOz => volumeOz * (abvPercent / 100);
  double get standardDrinks => pureAlcoholOz / 0.6;
}

const List<DrinkPreset> kDrinkPresets = [
  DrinkPreset(name: 'Regular Beer',    volumeOz: 12,  abvPercent: 5.0,  emoji: '🍺'),
  DrinkPreset(name: 'Light Beer',      volumeOz: 12,  abvPercent: 4.2,  emoji: '🍻'),
  DrinkPreset(name: 'Craft IPA',       volumeOz: 12,  abvPercent: 7.0,  emoji: '🍺'),
  DrinkPreset(name: 'Glass of Wine',   volumeOz: 5,   abvPercent: 12.0, emoji: '🍷'),
  DrinkPreset(name: 'Glass of Wine (Heavy)', volumeOz: 5, abvPercent: 15.0, emoji: '🍷'),
  DrinkPreset(name: 'Shot of Spirits', volumeOz: 1.5, abvPercent: 40.0, emoji: '🥃'),
  DrinkPreset(name: 'Cocktail',        volumeOz: 4,   abvPercent: 20.0, emoji: '🍸'),
  DrinkPreset(name: 'Hard Seltzer',    volumeOz: 12,  abvPercent: 5.0,  emoji: '🫧'),
  DrinkPreset(name: 'Malt Beverage',   volumeOz: 16,  abvPercent: 8.0,  emoji: '🍺'),
];