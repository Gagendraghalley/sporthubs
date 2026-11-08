/// The gym module's venue permissions (20261108000003_gym_permissions.sql):
/// the database checks them; the app uses them to decide what to show.
/// Income is the core's VenuePermission.income.
abstract final class GymPermission {
  /// Register members at the front desk, change their details and photo,
  /// reissue their cards (20261108000004_gym_registration.sql).
  static const register = 'gym.register';

  /// See members, their memberships and check-ins.
  static const members = 'gym.members';

  /// Confirm payments to start memberships, and cancel requests.
  static const payments = 'gym.payments';

  /// Check members in.
  static const checkIn = 'gym.check_in';

  /// Plans and prices.
  static const plans = 'gym.plans';
}
