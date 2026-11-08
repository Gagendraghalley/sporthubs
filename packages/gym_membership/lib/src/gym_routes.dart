/// The gym module's pages. Everything lives under /gyms, so the router can
/// close them all while the module is turned off.
abstract final class GymRoutes {
  static const gyms = '/gyms';

  // Public information, for visitors: the gyms on SportsHub and each gym's
  // page (its packages, prices and how to reach it).
  static const gym = '/gyms/:id';

  // Running a gym: its staff, by their role's permissions.
  static const dashboard = '/gyms/:id/manage';
  static const checkIn = '/gyms/:id/manage/check-in';
  static const members = '/gyms/:id/manage/members';
  static const registerMember = '/gyms/:id/manage/members/new';
  static const member = '/gyms/:id/manage/members/:memberId';
  static const editMember = '/gyms/:id/manage/members/:memberId/edit';

  /// Straight after registering them: done, and their QR card to send.
  static const memberRegistered = '/gyms/:id/manage/members/:memberId/registered';
  static const plans = '/gyms/:id/manage/plans';
  static const income = '/gyms/:id/manage/income';
  static const reports = '/gyms/:id/manage/reports';

  /// Gone (members no longer ask to join in the app); old notifications
  /// that point here open Members.
  static const requests = '/gyms/:id/manage/requests';

  static String gymFor(String id) => '/gyms/$id';
  static String dashboardFor(String id) => '/gyms/$id/manage';
  static String checkInFor(String id) => '/gyms/$id/manage/check-in';
  static String membersFor(String id) => '/gyms/$id/manage/members';
  static String registerMemberFor(String id) => '/gyms/$id/manage/members/new';
  static String memberFor(String id, String memberId) => '/gyms/$id/manage/members/$memberId';
  static String editMemberFor(String id, String memberId) => '/gyms/$id/manage/members/$memberId/edit';
  static String memberRegisteredFor(String id, String memberId) => '/gyms/$id/manage/members/$memberId/registered';
  static String plansFor(String id) => '/gyms/$id/manage/plans';

  /// Packages, with the form for a new one open.
  static String newPlanFor(String id) => '/gyms/$id/manage/plans?new=1';
  static String incomeFor(String id) => '/gyms/$id/manage/income';
  static String reportsFor(String id) => '/gyms/$id/manage/reports';

  /// The gym whose staff page [path] is, if it's one.
  static String? gymIdIn(String path) =>
      RegExp(r'^/gyms/([0-9a-fA-F-]{36})/manage(/|$)').firstMatch(path)?.group(1);
}
