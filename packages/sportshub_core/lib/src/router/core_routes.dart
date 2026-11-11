/// The core's pages. Modules add their own (SportsHubModule.routes).
abstract final class CoreRoutes {
  static const root = '/';

  // Signing in: one account for the website and the apps.
  static const welcome = '/welcome';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const verify = '/verify';
  static const setPassword = '/set-password';

  /// The platform's Overview, and every service on it.
  static const home = '/home';
  static const services = '/services';
  static const account = '/account';
  static const editProfile = '/account/edit';
  static const notifications = '/notifications';

  // Venues: registering one (any type a module serves) and running it.
  static const registerVenue = '/register-venue';
  static const registerVenueForm = '/register-venue/:type';
  static const manage = '/manage';
  static const venueManage = '/manage/:id';
  static const editVenue = '/manage/:id/edit';
  static const venueStaff = '/manage/:id/staff';

  /// The venue's organisation's roles, and what each may do there.
  static const venueRoles = '/manage/:id/roles';
  static const venueRoleNew = '/manage/:id/roles/new';
  static const venueRole = '/manage/:id/roles/:roleId';

  // The SportsHub team.
  static const admin = '/admin';
  static const adminVenues = '/admin/venues';
  static const adminModules = '/admin/modules';
  static const adminUsers = '/admin/users';
  static const adminUser = '/admin/users/:id';
  static const adminRoles = '/admin/roles';
  static const adminRoleNew = '/admin/roles/new';
  static const adminRole = '/admin/roles/:id';
  static const adminMasters = '/admin/masters';
  static const adminOrganisations = '/admin/organisations';
  static const adminOrganisation = '/admin/organisations/:id';

  static String adminUserFor(String id) => '/admin/users/$id';

  /// Users: everyone, or the people who work at [organisation]'s venues.
  static String adminUsersFor(String? organisation) =>
      organisation == null ? adminUsers : '$adminUsers?org=$organisation';

  /// Roles and permissions: SportsHub-wide, or as [organisation] has them.
  static String adminRolesFor(String? organisation) =>
      organisation == null ? adminRoles : '$adminRoles?org=$organisation';

  /// A role; for an organisation, as it has the role.
  static String adminRoleFor(String id, {String? organisation}) =>
      organisation == null ? '/admin/roles/$id' : '/admin/roles/$id?org=$organisation';

  /// A new role of [scope]; with [organisation], that organisation's own.
  static String adminRoleNewFor(String scope, {String? organisation}) =>
      '$adminRoleNew?scope=$scope${organisation == null ? '' : '&org=$organisation'}';

  static String adminOrganisationFor(String id) => '/admin/organisations/$id';

  static String registerVenueFor(String type) => '/register-venue/$type';
  static String venueManageFor(String id) => '/manage/$id';
  static String editVenueFor(String id) => '/manage/$id/edit';
  static String venueStaffFor(String id) => '/manage/$id/staff';
  static String venueRolesFor(String id) => '/manage/$id/roles';
  static String venueRoleNewFor(String id) => '/manage/$id/roles/new';
  static String venueRoleFor(String id, String roleId) => '/manage/$id/roles/$roleId';

  static String signInFor(String next) => '$signIn?next=${Uri.encodeComponent(next)}';
  static String signUpFor(String? next) => next == null ? signUp : '$signUp?next=${Uri.encodeComponent(next)}';

  /// Pages visitors can open without an account.
  static const publicPaths = {welcome, signIn, signUp, verify, registerVenue};

  /// Pages only for visitors: signed-in users go on to their page.
  static const signedOutOnly = {welcome, signIn, signUp};
}
