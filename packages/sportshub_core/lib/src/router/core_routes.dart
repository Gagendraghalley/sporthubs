/// The core's pages. Modules add their own (SportsHubModule.routes).
abstract final class CoreRoutes {
  static const root = '/';

  // Signing in: one account for the website and the apps.
  static const welcome = '/welcome';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const verify = '/verify';
  static const setPassword = '/set-password';

  static const home = '/home';
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

  // The SportsHub team.
  static const admin = '/admin';
  static const adminVenues = '/admin/venues';
  static const adminModules = '/admin/modules';

  static String registerVenueFor(String type) => '/register-venue/$type';
  static String venueManageFor(String id) => '/manage/$id';
  static String editVenueFor(String id) => '/manage/$id/edit';
  static String venueStaffFor(String id) => '/manage/$id/staff';

  static String signInFor(String next) => '$signIn?next=${Uri.encodeComponent(next)}';
  static String signUpFor(String? next) => next == null ? signUp : '$signUp?next=${Uri.encodeComponent(next)}';

  /// Pages visitors can open without an account.
  static const publicPaths = {welcome, signIn, signUp, verify, registerVenue};

  /// Pages only for visitors: signed-in users go on to their page.
  static const signedOutOnly = {welcome, signIn, signUp};
}
