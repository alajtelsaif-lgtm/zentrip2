class FlexibleFlightSelection {
  final List<DateTime> departureMonths;
  final int tripDurationDays;

  const FlexibleFlightSelection({
    required this.departureMonths,
    required this.tripDurationDays,
  });

  bool get isValid =>
      departureMonths.isNotEmpty &&
      departureMonths.length <= 3 &&
      tripDurationDays >= 1 &&
      tripDurationDays <= 60;
}
