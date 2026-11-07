/// The gym module's pages. Everything lives under /gyms and /my-gym, so the
/// router can close them all while the module is turned off.
abstract final class GymRoutes {
  static const gyms = '/gyms';
  static const gym = '/gyms/:id';
  static const myGym = '/my-gym';

  // Running a gym: its staff (the database checks venue_staff).
  static const dashboard = '/gyms/:id/manage';
  static const checkIn = '/gyms/:id/manage/check-in';
  static const requests = '/gyms/:id/manage/requests';
  static const members = '/gyms/:id/manage/members';
  static const plans = '/gyms/:id/manage/plans';
  static const income = '/gyms/:id/manage/income';

  static String gymFor(String id) => '/gyms/$id';
  static String dashboardFor(String id) => '/gyms/$id/manage';
  static String checkInFor(String id) => '/gyms/$id/manage/check-in';
  static String requestsFor(String id) => '/gyms/$id/manage/requests';
  static String membersFor(String id) => '/gyms/$id/manage/members';
  static String plansFor(String id) => '/gyms/$id/manage/plans';
  static String incomeFor(String id) => '/gyms/$id/manage/income';
}
