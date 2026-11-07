import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';

class _Module extends SportsHubModule {
  const _Module(this.key);

  @override
  final String key;

  @override
  String get name => key;

  @override
  String get description => '';

  @override
  IconData get icon => Icons.star;

  @override
  List<String> get basePaths => const ['/gyms', '/my-gym'];

  @override
  List<VenueKind> get venueKinds => const [
        VenueKind(key: 'gym', label: 'Gym', description: '', icon: Icons.star),
      ];
}

void main() {
  group('visibleModules', () {
    const a = _Module('ground_booking');
    const b = _Module('gym_membership');
    const c = _Module('coaching');
    const rows = [
      AppModuleRow(key: 'gym_membership', name: 'Gym', isEnabled: true, sortOrder: 5),
      AppModuleRow(key: 'ground_booking', name: 'Grounds', isEnabled: false, sortOrder: 10),
    ];

    test('users see enabled modules only', () {
      expect(visibleModules([a, b, c], rows, isAdmin: false), [b]);
    });

    test('admins also see turned-off ones, in sort_order', () {
      expect(visibleModules([a, b, c], rows, isAdmin: true), [b, a]);
    });

    test('a module without an app_modules row stays hidden', () {
      expect(visibleModules([c], rows, isAdmin: true), isEmpty);
    });
  });

  test('a module owns its paths and nothing that only starts the same', () {
    const m = _Module('gym_membership');
    expect(m.ownsPath('/gyms'), isTrue);
    expect(m.ownsPath('/gyms/1/manage'), isTrue);
    expect(m.ownsPath('/gymsxyz'), isFalse);
    expect(m.servesVenueType('gym'), isTrue);
    expect(m.servesVenueType('ground'), isFalse);
  });

  group('BhutanTime', () {
    test('is UTC+6 whatever the device', () {
      final b = BhutanTime.toBhutan(DateTime.utc(2026, 11, 7, 20, 30));
      expect([b.year, b.month, b.day, b.hour, b.minute], [2026, 11, 8, 2, 30]);
    });

    test('days between dates', () {
      expect(BhutanTime.daysBetween(DateTime(2026, 2, 27), DateTime(2026, 3, 1)), 2);
      expect(BhutanTime.daysBetween(DateTime(2026, 3, 1), DateTime(2026, 2, 27)), -2);
      expect(BhutanTime.formatIsoDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(BhutanTime.parseDate('2026-11-07'), DateTime(2026, 11, 7));
    });
  });

  test('formatters', () {
    expect(formatNu(1500), 'Nu. 1,500');
    expect(formatNu(1000000), 'Nu. 1,000,000');
    expect(formatDuration(1), '1 day');
    expect(formatDuration(30), '1 month');
    expect(formatDuration(90), '3 months');
    expect(formatDuration(365), '1 year');
    expect(formatDuration(14), '2 weeks');
    expect(formatDuration(45), '45 days');
    expect(firstName('  Pema   Wangmo '), 'Pema');
    expect(firstName(''), 'there');
  });

  group('Validators', () {
    test('phones become +975 numbers', () {
      expect(Validators.normalizePhone('17123456'), '+97517123456');
      expect(Validators.normalizePhone('+975 17-12 34 56'), '+97517123456');
      expect(Validators.normalizePhone('97577123456'), '+97577123456');
      expect(Validators.normalizePhone('1234'), isNull);
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('', required: true), isNotNull);
    });

    test('emails, passwords and numbers', () {
      expect(Validators.email('pema@example.bt'), isNull);
      expect(Validators.email('pema@'), isNotNull);
      expect(Validators.password('1234567'), isNotNull);
      expect(Validators.password('12345678'), isNull);
      expect(Validators.wholeNumber('1500'), isNull);
      expect(Validators.wholeNumber('-1'), isNotNull);
      expect(Validators.wholeNumber('1.5'), isNotNull);
    });
  });

  test('a venue from the database', () {
    final v = Venue.fromJson({
      'id': 'v1',
      'type': 'gym',
      'name': 'Peak Fitness',
      'dzongkhag': 'Thimphu',
      'town': 'Changzamtog',
      'photos': ['https://x/a.jpg'],
      'verification_status': 'verified',
      'rating_average': 4.5,
      'rating_count': 2,
      'created_at': '2026-11-07T10:00:00Z',
    });
    expect(v.isVerified, isTrue);
    expect(v.place, 'Changzamtog, Thimphu');
    expect(v.coverPhoto, 'https://x/a.jpg');
    expect(v.hasLocation, isFalse);
  });

  test('income adds up completed payments by method', () {
    Payment p(int amount, String method, [String status = 'completed']) => Payment.fromJson({
          'id': '$amount$method',
          'venue_id': 'v1',
          'module_key': 'gym_membership',
          'amount': amount,
          'method': method,
          'status': status,
          'created_at': '2026-11-07T10:00:00Z',
          'payer': {'full_name': 'Pema'},
        });
    final s = IncomeSummary.of([p(1500, 'mbob'), p(1500, 'cash'), p(400, 'mbob'), p(900, 'cash', 'refunded')]);
    expect(s.total, 3400);
    expect(s.count, 3);
    expect(s.byMethod, {PaymentMethod.mbob: 1900, PaymentMethod.cash: 1500});
  });

  test('VenueRole', () {
    expect(VenueRole.canManage(VenueRole.manager), isTrue);
    expect(VenueRole.canManage(VenueRole.staff), isFalse);
    expect(VenueRole.canEditStaff(VenueRole.manager), isFalse);
    expect(VenueRole.canEditStaff(VenueRole.admin), isTrue);
  });
}
