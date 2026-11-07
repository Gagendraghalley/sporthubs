/// SportsHub's shared core: what every module builds on. Modules import
/// only this library, never each other.
library;

export 'src/admin/admin_repository.dart';
export 'src/auth/auth_repository.dart';
export 'src/config/env.dart';
export 'src/module/app_module_row.dart';
export 'src/module/module_providers.dart';
export 'src/module/sportshub_module.dart';
export 'src/notifications/app_notification.dart';
export 'src/notifications/notification_repository.dart';
export 'src/notifications/notifications_screen.dart' show NotificationBell;
export 'src/payments/payment.dart';
export 'src/payments/payment_repository.dart';
export 'src/profiles/profile.dart';
export 'src/profiles/profile_repository.dart';
export 'src/router/app_router.dart';
export 'src/router/core_routes.dart';
export 'src/router/route_guard.dart';
export 'src/shell/sportshub_app.dart';
export 'src/supabase/supabase_provider.dart';
export 'src/theme/app_theme.dart';
export 'src/theme/brand.dart';
export 'src/theme/theme_mode.dart';
export 'src/utils/bhutan_time.dart';
export 'src/utils/dzongkhags.dart';
export 'src/utils/formatters.dart';
export 'src/utils/friendly_error.dart';
export 'src/utils/launch.dart';
export 'src/utils/validators.dart';
export 'src/venues/venue.dart';
export 'src/venues/venue_repository.dart';
export 'src/venues/venue_widgets.dart';
export 'src/widgets/app_page.dart';
export 'src/widgets/common.dart';
export 'src/widgets/feedback.dart';
export 'src/widgets/form_fields.dart';
export 'src/widgets/logo.dart';
