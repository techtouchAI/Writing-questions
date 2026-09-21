enum Difficulty {
  easy,
  medium,
  hard;

  String get arabicLabel {
    switch (this) {
      case Difficulty.easy:
        return 'سهل';
      case Difficulty.medium:
        return 'متوسط';
      case Difficulty.hard:
        return 'صعب';
    }
  }

  static Difficulty fromString(String val) {
    return Difficulty.values.firstWhere(
      (e) => e.name == val,
      orElse: () => Difficulty.medium,
    );
  }
}
