# SportsHub

Play · Train · Book · Connect. One app for sport in Bhutan, on the web, Android and iOS, built from a shared **core** and one package per **module**:

| Module | Status | What it does |
|---|---|---|
| Ground booking (`ground_booking`) | On | Book grounds and follow tournaments. These still run on the ground booking website, and SportsHub links to it (see [Bringing ground booking in](#bringing-ground-booking-in-one-domain)). |
| Gym membership (`gym_membership`) | Built, off until you turn it on | The front desk registers members (details, webcam photo, package and its expiry date), sends them a QR card on WhatsApp, and checks them in with it. Owners set packages and prices, see income and choose their staff's roles. |

The backend is Supabase: database, security rules, server functions, the daily job and the account-deletion Edge Function. There is no other server.

## Layout

```
pubspec.yaml                  Dart pub workspace: run `flutter pub get` here
apps/sportshub_app/           the one Flutter app (web, Android, iOS); lib/main.dart lists the modules
packages/sportshub_core/      accounts, profiles, venues and staff, payments, notifications,
                              the module contract, router, home page, admin, theme
packages/ground_booking/      module 1: links to the ground booking website
packages/gym_membership/      module 2: gym plans, memberships, check-in, staff and owner pages
supabase/migrations/          core, then one migration per module
supabase/functions/           Edge Functions (delete-account, admin-users)
supabase/config.toml          auth settings (email codes) and function settings
supabase/templates/code.html  the sign-in email, showing the 6-digit code
supabase/test_users.sql       test accounts, one per role (test_users_remove.sql removes them)
tests/database/               end-to-end checks of the database rules
scripts/                      deploy_supabase.sh, build_web.sh, deploy_web.sh, test_database.sh
wrangler.jsonc                the website on Cloudflare Workers
```

Modules import only `sportshub_core`, never each other.

## Run the app

1. Put the backend on Supabase once (next section). That also writes `apps/sportshub_app/env.json`. Without it, copy `env.example.json` to `env.json` and fill in the Project URL and the anon (publishable) key from Supabase → Project Settings → API Keys. `env.json` is gitignored.
2. Run the website on http://localhost:3000 (3001 when 3000 is taken), from the `sporthubs` folder:

```sh
./scripts/run_web.sh              # opens Chrome on http://localhost:3000
./scripts/run_web.sh 3001         # a port of your choice
SERVE_ONLY=1 ./scripts/run_web.sh # just serve it; open the address in any browser
```

   In the terminal, `r` hot-reloads, `R` restarts and `q` quits. Or by hand:

```sh
cd apps/sportshub_app
flutter run -d chrome --web-port 3000 --dart-define-from-file=env.json   # website
flutter run --dart-define-from-file=env.json                             # phone or simulator
```

In VS Code, use the "SportsHub (website)" (port 3000), "SportsHub (website, port 3001)" and "SportsHub (phone)" launch configurations.

## Backend (Supabase)

Project: **SportsHub**, ref `iagqntjaywpdxvoxgfhl` (Singapore), `https://iagqntjaywpdxvoxgfhl.supabase.co`.

### Deploy

```sh
SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... scripts/deploy_supabase.sh
```

- `SUPABASE_ACCESS_TOKEN`: supabase.com/dashboard/account/tokens → Generate new token.
- `SUPABASE_DB_PASSWORD`: the database password set when the project was made (Database → Settings → Reset database password if it's lost).
- The database is reached through SportsHub's Session pooler, which works on networks without IPv6; it's built into the script. Deploying to a different project: set `SUPABASE_PROJECT_REF` and `SUPABASE_DB_URL` (that project's **Session pooler** string from the dashboard's Connect button, `[YOUR-PASSWORD]` included; the script puts the password in).
- The auth step fails ("Email template modification is not available for free tier projects…") until SMTP is set up (below). Migrations and functions are deployed before it.

The script applies only the migrations that aren't on the project yet, deploys the Edge Functions, pushes the auth settings in `supabase/config.toml`, and writes `env.json`. Run it again after any change in `supabase/`.

Rules for database changes: every change is a new file in `supabase/migrations/` (never edit one that's applied). Try it on a development project or with `scripts/test_database.sh` first, and back up before applying to the live project (Database → Backups).

### Email: set up SMTP before real users sign up

Sign-up and sign-in use a 6-digit code sent by email. Supabase's built-in email sender is only for trying things out: it sends a few emails an hour, and only to your team's addresses. Before launch, add an email provider (Resend, Brevo, Amazon SES...) under Authentication → Emails → SMTP Settings, sending from your SportsHub domain.

### Make yourself an admin

Sign up in the app, then in Supabase → SQL Editor:

```sql
update public.profiles set role = 'admin' where email = 'you@example.com';
```

That makes you a **super admin**: you can do everything. You see SportsHub admin on the home page: **Users**, **Roles and permissions**, **Master data**, **Venues to verify** and **Modules**. From there you make the rest of the team's accounts and give them roles, so the SQL editor is only needed for this first one. Users can't change their own role.

### Test accounts

To try SportsHub as each role: Supabase → SQL Editor → New query, paste `supabase/test_users.sql`, put a password of your own on its `PASSWORD` line, and Run. It makes **SportsHub Test Gym** (verified, with two packages) and one account per role, all with that password. They sign in with email and password, so no email has to arrive.

| Account | Role |
|---|---|
| `test.superadmin@example.com` | Super admin |
| `test.admin@example.com` | Administrator |
| `test.owner@example.com` | Owner of the test gym |
| `test.manager@example.com` | Manager |
| `test.frontdesk@example.com` | Front desk |
| `test.trainer@example.com` | Trainer |
| `test.member@example.com` | Member with an account: 3 months of Monthly at the test gym |

Each role made under Roles and permissions gets `test.<role key>@example.com` too. Run it again after adding a role, or to put the passwords and roles back. While gym membership is off, only the super admin and the administrator see the gym's pages. They're real accounts, a super admin among them: remove them before launch with `supabase/test_users_remove.sql`.

### Turning gym membership on

It starts off (`app_modules.is_enabled = false`). While it's off, everyone except super admins and people with `modules.manage` sees nothing of it, and its pages send people home. They see and use everything, so they can test it in production. Then:

1. As an admin, register a gym (Register your venue → Gym), add plans, and verify it under Admin → Venues to verify.
2. Pilot it with a few members.
3. Admin → Modules → turn Gym membership on.

### Daily job

`gym_daily_maintenance()` runs every day at 00:05 Bhutan time with pg_cron. It expires memberships past their end, tells members 3 days before the end, and closes requests left for 30 days. Check it's scheduled with `select * from cron.job;`. If the migration couldn't schedule it, turn on pg_cron under Database → Extensions and run in the SQL editor:

```sql
select cron.schedule('gym-daily-maintenance', '5 18 * * *', 'select public.gym_daily_maintenance()');
```

## How it fits together

### A platform of services

SportsHub is a multi-service platform: gym management is the first service, and others (ground booking, coaching...) plug in the same way. Each service is a module. The platform owns the frame; a service only describes itself.

**The side menu is service-driven, not feature-driven** (`PlatformShell`, in sportshub_core):

1. The platform's own pages: **Overview** (`/home`: a welcome, every service's shortcuts and card, what needs attention), **My services** (`/services`: every service, in use or not yet set up) and **Notifications**.
2. **Services**: one collapsible section per service: its icon and colour, the person's role in it, what it's working on (a gym, with a switcher for someone at several) and its pages under small headings, as their roles allow. The section of the page in use opens; the others fold to one line, so 20 services stay a short list (from 7, a box to find one).
3. **Administration** for the SportsHub team, as a section like a service's.
4. Who is signed in: account, light/dark, sign out.

Folded (a computer), the menu is icons and a service's icon opens its pages beside it; on a phone it's a drawer. Every page in a service shows the service and its gym over its title, and a **New** menu of the service's shortcuts.

### Module contract (`SportsHubModule`, in sportshub_core)

| Member | Purpose |
|---|---|
| `key` | matches `app_modules.key` |
| `name`, `description`, `icon`, `color` | how the service appears: its menu section, cards and accents |
| `basePaths` | its pages, e.g. `['/gyms']`; closed while it's off |
| `routes` | its GoRoutes, in the platform's frame |
| `publicPaths` | pages visitors can open without an account |
| `venueKinds` | the venue types it serves, offered on Register your venue |
| `navigation(ref, location)` | its section of the side menu (`ServiceNav`): its scope (the gym), its pages in `NavSection`s (each `NavDestination` only if `access.can(...)`), its shortcuts (`ServiceAction`); a way to set it up when there's nothing yet |
| `buildOverviewCard()` | its card on Overview and My services (`ServiceCard`, `ServiceStats`); a plain one if null |
| `playerMenuItems()` | for players and members (pages or external links) |
| `managerMenuItems(venue, access)` | on a venue's Manage page: what `access.can(...)` allows |
| `buildManagerSection()`, `buildWelcome()` | optional manage widget, and the visitors' Welcome page |

### Design system (sportshub_core)

- **Type and colour**: Plus Jakarta Sans everywhere (`brandFont`, through the theme); navy, orange and blue from the logo (`BrandColors`, `context.brand`), light and dark.
- **Dashboard kit** (`dashboard_kit.dart`): `ConsoleCard`, `ConsoleKpi` (numbers count up), `ConsoleLineChart` (draws itself in), `ConsoleBarChart` (bars grow in; tap and tooltips), `ConsoleRing` (sweeps round), `ConsoleShareRow`, `ConsoleRangePicker`.
- **Motion** (`motion.dart`): `AnimatedCount`, `HoverLift` (cards rise under the mouse), `FadeSlideIn` / `staggered` (cards arrive one after another), `LoadingSkeleton` (the shape of the page, shimmering, instead of a spinner; `AsyncValueView` uses it). Pages fade and rise in (`SoftRiseTransitionsBuilder`). It all stands still when the device asks for less motion.
- **Feedback**: `runAction` / `showFeedback` show a tick or a warning in a floating bar; `EmptyState` says what to do next.
- **Service cards** (`service_cards.dart`): `ServiceCard`, `ServiceStat(s)`, `QuickActionTile`.

### Roles and permissions

A **permission** is something the database checks (`permissions`; the keys are fixed in the migrations). A **role** is a named set of permissions (`roles`, `role_permissions`), made and changed under Admin → Roles and permissions.

| Scope | Permissions | Roles that come with SportsHub |
|---|---|---|
| SportsHub team (`user_roles`) | `users.manage`, `roles.manage`, `masters.manage`, `venues.verify`, `modules.manage` | Administrator (all five) |
| A venue (`venue_staff.role`) | `venue.edit`, `venue.staff`, `venue.income`, and the gym's `gym.members`, `gym.payments`, `gym.check_in`, `gym.plans` | Owner (always everything), Manager, Front desk (`staff`), Trainer |

- **Super admins** (`profiles.role = 'admin'`) can do everything. Only another super admin makes or unmakes one, and nobody can unmake themselves.
- **Nobody can give a permission they don't have.** Team roles and venue roles can only be given, changed or taken away by someone holding every permission in them. Only super admins and user managers make someone a venue's Owner, and a venue always keeps one.
- **Turning things off.** A role that is turned off gives nobody anything. An account that is turned off (Admin → Users) loses every role, and the `admin-users` Edge Function blocks its sign-in until it's turned on again. Memberships and history stay.
- **Making accounts.** Admin → Users → New user, or a venue's Staff → Add staff → Make their account. They sign in with their email and the emailed code. The `admin-users` Edge Function makes the account; the role changes run as the person asking, so the database rules above still decide.
- One person can own a gym and be a member at another.

### Master data

`dzongkhags` → `gewogs` (and thromdes) → `villages`: 20, 216 and 4,499 rows, from the BRECSA service's `tbl_dzongkhag`, `tbl_gewog` and `tbl_chiwog` (`20261108000002_master_locations_data.sql` says what was cleaned). Everyone reads the rows that are on. People with `masters.manage` add, rename and turn rows off under Admin → Master data. Rows are never deleted, so addresses keep pointing at them. Forms use `LocationFields` (dzongkhag, then gewog, then village).

### Security

Row Level Security is on for every table. Members see only their own memberships, check-ins and payments; a gym's staff see only what their role's permissions allow at that gym. Money, membership status, roles and master data change only through `security definer` functions that check the caller's permissions (`has_permission`, `has_venue_permission`). Unverified venues are hidden from everyone but their staff, admins and venue verifiers. The service-role key lives only in Edge Functions.

### Gym membership

Members walk in; they need no SportsHub account.

1. **Register** (Register member, `gym.register`): the front desk fills in the client's form (name, phone, email, dzongkhag, gewog and village, occupation, emergency contact, blood group, date of birth, date of joining, medical issues), snaps their photo with the webcam (the camera on a phone; Retake before saving, or Upload), and sells a package (`gym.payments`): the package, how many months (1 to 24), and what they paid. The **expiry date** is worked out, not typed: the same date, months later (joining 8 Nov 2026 for 3 months expires on 8 Feb 2027, and they can still come in that day). `gym_register_member` saves it all in `gym_members`, `gym_subscriptions` and `payments`.
2. **Card**: the page after registering shows the package, its expiry date, their details and their **QR card**: Download card (in a browser) or Share card (on a phone, WhatsApp is in the share sheet), and WhatsApp, which opens their chat with a message ready. The card holds only `sportshub:gym-member:<random token>`: no phone, birthday or medical notes. New card (on their page) makes the old one stop working.
3. **Check in** (`gym.check_in`): scan the card with the camera, a USB QR scanner (it types into the member code box, which keeps the cursor on a computer), or type the 6-character member code (`gym_check_in_member`, `gym_check_in_by_code`). It's recorded only if a package at that gym covers today. The desk sees **Checked in** with their photo, days left and medical notes, or **Not checked in** with why ("…'s package ended on …") and a button to renew.
4. **Renew**: on their page. A renewal starts on the day the current package expires, so the dates don't drift (8 Feb, 8 May, 8 Aug), or today once it has ended (`gym_renew_member`).
5. **Owner**: a dashboard (today's numbers, shortcuts, what needs attention, a getting-started checklist for a new gym), packages and prices (members on each, times sold), the members register (search, status filters with counts, sort, table or cards), income (12 months, by method, every payment), **reports & analytics** (new members, visits by day and hour, renewal rate, package mix, most regular members, and what it all says) and staff with their roles.

Members with a SportsHub account (`member_id`) still work underneath: their QR code is `sportshub:member:<account id>`, and `gym_activate_subscription` runs their memberships by the plan's days.

Dates are Bhutan dates (Asia/Thimphu), both ends included.

### Logo, splash and loader

- **Logo** (`SportsHubLogo`): navy lettering for light backgrounds (`sportshub_logo.png`, `sportshub_mark.png`), and white lettering with a brighter blue S for dark ones (`*_on_dark.png`). It follows the theme. Places that are navy in both themes (the side menu, the welcome page's footer, the splash) pass `onDark: true`.
- **Splash** (`SportsHubSplash`): the white logo in the middle of the navy, 240 wide on a phone and 320 on anything bigger, with an orange bar under it. It shows while the modules load at start (`SplashGate` fades it into the page). The launch screens draw the same logo at the same size and place, so the handover doesn't jump. If you change one, change them all: `web/index.html` and `web/splash/`, Android's `res/drawable*/launch_background.xml`, `splash_logo.png`, `splash_icon.png` and `values*-v31/styles.xml` (Android 12+ shows the mark in a circle), and iOS's `LaunchScreen.storyboard`, `LaunchImage` and `LaunchBackground`. iOS caches its launch screen, so delete the app and reinstall it to see a change.
- **Loader** (`SportsHubLoader`): the orange-and-blue spinner, for the few places that wait without a shape to show. Pages and lists waiting on data show `LoadingSkeleton` (through `AsyncValueView`). Spinners inside buttons stay Flutter's plain one.

## Adding a module (e.g. coaching)

1. `packages/coaching`, depending on `sportshub_core`; add it to the root `pubspec.yaml` workspace list and to the app's `pubspec.yaml`.
2. `class CoachingModule extends SportsHubModule`, with its `color`, `navigation` (its menu section) and, if it wants one, `buildOverviewCard`; and one line in `apps/sportshub_app/lib/main.dart`. The side menu, Overview and My services pick it up: nothing else in the app changes.
3. A migration: `coaching_*` tables (linked to `venues`), RLS, functions, and
   `insert into public.app_modules (key, name, is_enabled, sort_order) values ('coaching', 'Coaching', false, 30);`
4. Test it as an admin, then turn it on.

## Bringing ground booking in (one domain)

All modules are meant to run from one domain. Ground booking already owns its paths in SportsHub (`/grounds`, `/grounds/venue/:id`, `/tournaments`, `/tournaments/:id`, `/register-ground`, the same hash URLs the booking website uses). For now those paths hand over to the website. To bring it in:

1. Move its screens into `packages/ground_booking` behind those same routes, so shared links keep working.
2. Add a migration with its tables (`ground_*`, linked to `venues`), its venue types (futsal, football...), and its deposits written to `payments`.
3. Remove `externalUrl`/`externalRegisterUrl` from `GroundBookingModule`.
4. Point the old domain at the SportsHub website.

## Website on Cloudflare

The website is a Cloudflare Worker named `sporthubs` (`wrangler.jsonc`) that serves the Flutter web build as static files: https://sporthubs.gagenghaley123.workers.dev. The `name` in `wrangler.jsonc` must match the Worker's name in the dashboard, or Cloudflare's GitHub builds won't deploy.

From your computer (after `scripts/deploy_supabase.sh` has written `env.json`):

```sh
CLOUDFLARE_API_TOKEN=... scripts/deploy_web.sh
```

Make the token at dash.cloudflare.com/profile/api-tokens → Create Token → "Edit Cloudflare Workers" template. Alternatively, run `npx wrangler login` once and leave the token out.

Or from GitHub, on every push: Cloudflare → Workers & Pages → Create application → Import a repository → `sporthubs`, with:

- Build command: `bash scripts/build_web.sh`
- Deploy command: `npx wrangler deploy`
- Build variables: `SUPABASE_URL` = `https://iagqntjaywpdxvoxgfhl.supabase.co`, `SUPABASE_ANON_KEY` = the anon (publishable) key. It's public: it ships inside the website anyway, and the database rules protect the data.

When it moves to its own domain, add the domain to the Worker (Settings → Domains & Routes) and to `site_url` in `supabase/config.toml`, then run the Supabase deploy again.

## Releasing

- **Website**: see [Website on Cloudflare](#website-on-cloudflare). `scripts/build_web.sh` builds `apps/sportshub_app/build/web`, which any static host can serve; URLs use `/#/`, so no rewrites are needed.
- **Android**: application id `bt.sportshub.app`. Add a release signing key before uploading to Google Play.
- **iOS**: bundle id `bt.sportshub.app`. Set your team in Xcode (`ios/Runner.xcworkspace`).
- App icons and in-app logos are made from the SportsHub logo (`packages/sportshub_core/assets/images/`). Replace those files and the icon sets to change them.

## Tests

```sh
(cd packages/sportshub_core && flutter test)
(cd packages/gym_membership && flutter test)
(cd packages/ground_booking && flutter test)
(cd apps/sportshub_app && flutter test)
scripts/test_database.sh      # needs a local PostgreSQL (brew install postgresql)
```

`scripts/test_database.sh` runs `tests/database/scenario_test.sql` (memberships end to end) and `access_test.sql` (master data, roles and permissions).
