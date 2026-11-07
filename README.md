# SportsHub

Play · Train · Book · Connect. One app for sport in Bhutan, on the web, Android and iOS, built from a shared **core** and one package per **module**:

| Module | Status | What it does |
|---|---|---|
| Ground booking (`ground_booking`) | On | Book grounds and follow tournaments. These still run on the ground booking website, and SportsHub links to it (see [Bringing ground booking in](#bringing-ground-booking-in-one-domain)). |
| Gym membership (`gym_membership`) | Built, off until you turn it on | Members find a gym, ask for a plan, pay the gym, and check in with a QR code. Gym staff confirm payments and check members in; owners set plans and see income. |

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
supabase/functions/           Edge Functions (delete-account)
supabase/config.toml          auth settings (email codes) and function settings
supabase/templates/code.html  the sign-in email, showing the 6-digit code
tests/database/               end-to-end checks of the database rules
scripts/                      deploy_supabase.sh, build_web.sh, deploy_web.sh, test_database.sh
wrangler.jsonc                the website on Cloudflare Workers
```

Modules import only `sportshub_core`, never each other.

## Run the app

1. Put the backend on Supabase once (next section). That also writes `apps/sportshub_app/env.json`. Without it, copy `env.example.json` to `env.json` and fill in the Project URL and the anon (publishable) key from Supabase → Project Settings → API Keys. `env.json` is gitignored.
2. Run:

```sh
cd apps/sportshub_app
flutter run -d chrome --web-port 8080 --dart-define-from-file=env.json   # website
flutter run --dart-define-from-file=env.json                             # phone or simulator
```

In VS Code, use the "SportsHub (website)" and "SportsHub (phone)" launch configurations.

## Backend (Supabase)

Project: **SportsHub**, ref `iagqntjaywpdxvoxgfhl` (Singapore), `https://iagqntjaywpdxvoxgfhl.supabase.co`.

### Deploy

```sh
SUPABASE_ACCESS_TOKEN=sbp_... SUPABASE_DB_PASSWORD=... scripts/deploy_supabase.sh
```

- `SUPABASE_ACCESS_TOKEN`: supabase.com/dashboard/account/tokens → Generate new token.
- `SUPABASE_DB_PASSWORD`: the database password set when the project was made (Project Settings → Database → Reset database password if it's lost).

The script applies only the migrations that aren't on the project yet, deploys the Edge Functions, pushes the auth settings in `supabase/config.toml`, and writes `env.json`. Run it again after any change in `supabase/`.

Rules for database changes: every change is a new file in `supabase/migrations/` (never edit one that's applied). Try it on a development project or with `scripts/test_database.sh` first, and back up before applying to the live project (Database → Backups).

### Email: set up SMTP before real users sign up

Sign-up and sign-in use a 6-digit code sent by email. Supabase's built-in email sender is only for trying things out: it sends a few emails an hour, and only to your team's addresses. Before launch, add an email provider (Resend, Brevo, Amazon SES...) under Authentication → Emails → SMTP Settings, sending from your SportsHub domain.

### Make yourself an admin

Sign up in the app, then in Supabase → SQL Editor:

```sql
update public.profiles set role = 'admin' where email = 'you@example.com';
```

Admins see SportsHub admin on the home page: **Venues to verify** and **Modules**. Users can't change their own role; only the SQL editor can.

### Turning gym membership on

It starts off (`app_modules.is_enabled = false`). While it's off, everyone except admins sees nothing of it, and its pages send people home. Admins see and use everything, so they can test it in production. Then:

1. As an admin, register a gym (Register your venue → Gym), add plans, and verify it under Admin → Venues to verify.
2. Pilot it with a few members.
3. Admin → Modules → turn Gym membership on.

### Daily job

`gym_daily_maintenance()` runs every day at 00:05 Bhutan time with pg_cron. It expires memberships past their end, tells members 3 days before the end, and closes requests left for 30 days. Check it's scheduled with `select * from cron.job;`. If the migration couldn't schedule it, turn on pg_cron under Database → Extensions and run in the SQL editor:

```sql
select cron.schedule('gym-daily-maintenance', '5 18 * * *', 'select public.gym_daily_maintenance()');
```

## How it fits together

### Module contract (`SportsHubModule`, in sportshub_core)

| Member | Purpose |
|---|---|
| `key` | matches `app_modules.key` |
| `name`, `description`, `icon` | how the module appears |
| `basePaths` | its pages, e.g. `['/gyms', '/my-gym']`; closed while it's off |
| `routes` | its GoRoutes |
| `publicPaths` | pages visitors can open without an account |
| `venueKinds` | the venue types it serves, offered on Register your venue |
| `playerMenuItems()` | for players and members (pages or external links) |
| `managerMenuItems(venue, role)` | on a venue's Manage page, per role |
| `buildHomeSection()`, `buildManagerSection()` | optional home and manage widgets |

### Roles

- **Platform role** (`profiles.role`): `user` (everyone) or `admin` (the SportsHub team: verify venues, turn modules on and off).
- **Venue roles** (`venue_staff`, per venue): `owner`, `manager`, `staff`. Owners add staff by their SportsHub email. Managers change details, plans and prices and see income. Staff check members in and confirm payments. One person can own a gym and be a member at another.

### Security

Row Level Security is on for every table. Members see only their own memberships, check-ins and payments; a gym's staff see only that gym's. Money and membership status change only through `security definer` functions that check the caller's venue role. Unverified venues are hidden from everyone but their staff and admins. The service-role key lives only in Edge Functions.

### Gym membership

1. **Join**: a member picks a plan on a gym's page (`gym_request_subscription`) → pending. They pay the gym by mBoB or cash.
2. **Confirm**: staff open Membership requests, enter the amount, method and mBoB journal number (`gym_activate_subscription`). The membership starts today, or for a renewal the day after the current one ends. The payment goes into `payments`.
3. **Check in**: staff scan the member's QR code (`sportshub:member:<account id>`) or type their 6-character member code (`gym_check_in`, `gym_check_in_by_code`). It works only with a membership at that gym covering today; otherwise staff see why.
4. **Owner**: plans and prices, members (active, ending soon, ended), income by month, staff.

Dates are Bhutan dates (Asia/Thimphu), both ends included.

## Adding a module (e.g. coaching)

1. `packages/coaching`, depending on `sportshub_core`; add it to the root `pubspec.yaml` workspace list and to the app's `pubspec.yaml`.
2. `class CoachingModule extends SportsHubModule`, and one line in `apps/sportshub_app/lib/main.dart`.
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

The website is a Cloudflare Worker named `sportshub` (`wrangler.jsonc`) that serves the Flutter web build as static files: https://sportshub.gagen123.workers.dev.

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
