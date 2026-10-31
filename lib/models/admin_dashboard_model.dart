class AdminDashboardData {
  final int customerCount;
  final int newCustomers;
  final int totalUserCount;
  final int partnerCount;
  final int activePartnerListingCount;
  final int reservationCount;
  final int flightCount;
  final int serviceBookingCount;
  final int transferCount;
  final double bookedValue;
  final List<AdminReservation> recentReservations;

  const AdminDashboardData({
    required this.customerCount,
    required this.newCustomers,
    this.totalUserCount = 0,
    this.partnerCount = 0,
    this.activePartnerListingCount = 0,
    required this.reservationCount,
    required this.flightCount,
    required this.serviceBookingCount,
    required this.transferCount,
    required this.bookedValue,
    required this.recentReservations,
  });

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>;
    final reservations = json['recent_reservations'] as List? ?? const [];
    return AdminDashboardData(
      customerCount: _asInt(summary['customer_count']),
      newCustomers: _asInt(summary['new_customers_30d']),
      totalUserCount:
          _asInt(summary['total_user_count'] ?? summary['customer_count']),
      partnerCount: _asInt(summary['partner_count']),
      activePartnerListingCount:
          _asInt(summary['active_partner_listing_count']),
      reservationCount: _asInt(summary['reservation_count']),
      flightCount: _asInt(summary['flight_count']),
      serviceBookingCount: _asInt(summary['service_booking_count']),
      transferCount: _asInt(summary['transfer_count']),
      bookedValue: _asDouble(summary['booked_value']),
      recentReservations: reservations
          .map(
              (item) => AdminReservation.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AdminPartner {
  final int id;
  final String name;
  final String slug;
  final String serviceType;
  final String status;
  final DateTime? createdAt;
  final int accountCount;
  final String contactEmails;
  final int listingCount;

  const AdminPartner({
    required this.id,
    required this.name,
    required this.slug,
    required this.serviceType,
    required this.status,
    required this.createdAt,
    required this.accountCount,
    required this.contactEmails,
    required this.listingCount,
  });

  bool get isActive => status.toLowerCase() == 'active';

  factory AdminPartner.fromJson(Map<String, dynamic> json) => AdminPartner(
        id: _asInt(json['id']),
        name: '${json['name'] ?? ''}',
        slug: '${json['slug'] ?? ''}',
        serviceType: '${json['service_type'] ?? ''}',
        status: '${json['status'] ?? 'inactive'}',
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
        accountCount: _asInt(json['account_count']),
        contactEmails: '${json['contact_emails'] ?? ''}',
        listingCount: _asInt(json['listing_count']),
      );
}

class AdminReservation {
  final String id;
  final String type;
  final String title;
  final String customerName;
  final DateTime? reservationDate;
  final double amount;
  final String status;

  const AdminReservation({
    required this.id,
    required this.type,
    required this.title,
    required this.customerName,
    required this.reservationDate,
    required this.amount,
    required this.status,
  });

  factory AdminReservation.fromJson(Map<String, dynamic> json) =>
      AdminReservation(
        id: '${json['id'] ?? ''}',
        type: '${json['type'] ?? ''}',
        title: '${json['title'] ?? ''}',
        customerName: '${json['customer_name'] ?? ''}',
        reservationDate: DateTime.tryParse('${json['reservation_date'] ?? ''}'),
        amount: _asDouble(json['amount']),
        status: '${json['status'] ?? ''}',
      );
}

class AdminCustomer {
  final String id;
  final String name;
  final String email;
  final String phone;
  final DateTime? joinedAt;
  final int reservationCount;

  const AdminCustomer({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.joinedAt,
    required this.reservationCount,
  });

  factory AdminCustomer.fromJson(Map<String, dynamic> json) => AdminCustomer(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        email: '${json['email'] ?? ''}',
        phone: '${json['phone'] ?? ''}',
        joinedAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
        reservationCount: _asInt(json['reservation_count']),
      );
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
