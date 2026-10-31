import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/admin_dashboard_model.dart';

void main() {
  test('admin partner parsing tolerates optional database columns', () {
    final active = AdminPartner.fromJson({
      'id': 18,
      'name': 'Libya Wings',
      'service_type': 'airline',
      'status': 'active',
      'account_count': 1,
      'contact_emails': 'partner@example.com',
      'listing_count': 4,
    });
    final inactive = AdminPartner.fromJson({
      'id': 19,
      'name': 'Archived partner',
    });

    expect(active.isActive, isTrue);
    expect(active.accountCount, 1);
    expect(active.listingCount, 4);
    expect(inactive.isActive, isFalse);
    expect(inactive.contactEmails, isEmpty);
    expect(inactive.createdAt, isNull);
  });
}
