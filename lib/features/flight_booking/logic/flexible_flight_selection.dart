class FlexibleFlightSelection {
  final List<DateTime> departureMonths;
  final int tripDurationDays;
  final bool weekendsOnly;
  final bool isCustomDuration;

  const FlexibleFlightSelection({
    required this.departureMonths,
    required this.tripDurationDays,
    this.weekendsOnly = false,
    this.isCustomDuration = false,
  });

  bool get isValid =>
      departureMonths.isNotEmpty &&
      departureMonths.length <= 3 &&
      tripDurationDays >= 1 &&
      tripDurationDays <= 60 &&
      (!weekendsOnly || tripDurationDays == 2);
}
