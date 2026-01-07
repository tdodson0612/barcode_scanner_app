// lib/models/tracker_entry.dart

class TrackerEntry {
  final String date; // YYYY-MM-DD
  final String? breakfast;
  final String? breakfastAmount;
  final String? lunch;
  final String? lunchAmount;
  final String? dinner;
  final String? dinnerAmount;
  final String? snack;
  final String? snackAmount;
  final String? exercise; // "30 minutes", "1 hour"
  final String? waterIntake; // "8 cups", "64 oz"
  final int dailyScore; // Calculated score (0-100)

  TrackerEntry({
    required this.date,
    this.breakfast,
    this.breakfastAmount,
    this.lunch,
    this.lunchAmount,
    this.dinner,
    this.dinnerAmount,
    this.snack,
    this.snackAmount,
    this.exercise,
    this.waterIntake,
    required this.dailyScore,
  });

  // JSON serialization
  Map<String, dynamic> toJson() => {
        'date': date,
        'breakfast': breakfast,
        'breakfastAmount': breakfastAmount,
        'lunch': lunch,
        'lunchAmount': lunchAmount,
        'dinner': dinner,
        'dinnerAmount': dinnerAmount,
        'snack': snack,
        'snackAmount': snackAmount,
        'exercise': exercise,
        'waterIntake': waterIntake,
        'dailyScore': dailyScore,
      };

  factory TrackerEntry.fromJson(Map<String, dynamic> json) => TrackerEntry(
        date: json['date'] ?? '',
        breakfast: json['breakfast'],
        breakfastAmount: json['breakfastAmount'],
        lunch: json['lunch'],
        lunchAmount: json['lunchAmount'],
        dinner: json['dinner'],
        dinnerAmount: json['dinnerAmount'],
        snack: json['snack'],
        snackAmount: json['snackAmount'],
        exercise: json['exercise'],
        waterIntake: json['waterIntake'],
        dailyScore: json['dailyScore'] ?? 0,
      );

  // Helper: Check if entry is empty
  bool get isEmpty =>
      breakfast == null &&
      lunch == null &&
      dinner == null &&
      snack == null &&
      exercise == null &&
      waterIntake == null;

  // Helper: Get total meals count
  int get mealCount {
    int count = 0;
    if (breakfast != null && breakfast!.isNotEmpty) count++;
    if (lunch != null && lunch!.isNotEmpty) count++;
    if (dinner != null && dinner!.isNotEmpty) count++;
    if (snack != null && snack!.isNotEmpty) count++;
    return count;
  }

  // Helper: Create copy with updated fields
  TrackerEntry copyWith({
    String? date,
    String? breakfast,
    String? breakfastAmount,
    String? lunch,
    String? lunchAmount,
    String? dinner,
    String? dinnerAmount,
    String? snack,
    String? snackAmount,
    String? exercise,
    String? waterIntake,
    int? dailyScore,
  }) {
    return TrackerEntry(
      date: date ?? this.date,
      breakfast: breakfast ?? this.breakfast,
      breakfastAmount: breakfastAmount ?? this.breakfastAmount,
      lunch: lunch ?? this.lunch,
      lunchAmount: lunchAmount ?? this.lunchAmount,
      dinner: dinner ?? this.dinner,
      dinnerAmount: dinnerAmount ?? this.dinnerAmount,
      snack: snack ?? this.snack,
      snackAmount: snackAmount ?? this.snackAmount,
      exercise: exercise ?? this.exercise,
      waterIntake: waterIntake ?? this.waterIntake,
      dailyScore: dailyScore ?? this.dailyScore,
    );
  }
}