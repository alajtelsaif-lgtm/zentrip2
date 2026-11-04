class PaymentAttemptReceipt {
  final int? attemptId;
  final bool paid;
  final String status;

  const PaymentAttemptReceipt({
    required this.attemptId,
    required this.paid,
    required this.status,
  });

  factory PaymentAttemptReceipt.fromJson(Map<String, dynamic> json) {
    final rawId = json['attempt_id'];
    return PaymentAttemptReceipt(
      attemptId: rawId is num ? rawId.toInt() : int.tryParse('$rawId'),
      paid: json['paid'] == true,
      status: (json['status'] ?? (json['paid'] == true ? 'success' : 'failed'))
          .toString(),
    );
  }
}
