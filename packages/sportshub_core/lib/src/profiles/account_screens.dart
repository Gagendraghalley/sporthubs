import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../theme/theme_mode.dart';
import '../utils/validators.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import '../widgets/responsive.dart';
import 'profile.dart';
import 'profile_repository.dart';

/// The signed-in user's page: their profile, appearance,
/// signing out and deleting the account.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    return AppPage(
      title: 'Account',
      body: AsyncValueView<Profile?>(
        value: profile,
        onRetry: () => ref.invalidate(myProfileProvider),
        data: (p) => ListView(
          padding: pagePadding(context),
          children: [
            ResponsiveColumns(
              first: [
            const SectionTitle('Profile'),
            if (p != null) _ProfileCard(profile: p),
            const SizedBox(height: 12),
            MenuTile(
              icon: Icons.edit_outlined,
              title: 'Edit profile',
              subtitle: 'Name, phone and dzongkhag',
              onTap: () => context.push(CoreRoutes.editProfile),
            ),
            ],
              // Gyms, registering one and admin are in the menu.
              second: [
            const SectionTitle('Settings'),
            const _AppearanceCard(),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
              onPressed: () async {
                await ref.read(authRepositoryProvider).signOut();
                if (context.mounted) context.go(CoreRoutes.welcome);
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: context.brand.danger),
              onPressed: () => _deleteAccount(context, ref),
              child: const Text('Delete my account'),
            ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final sure = await confirmAction(
      context,
      title: 'Delete your account?',
      message: 'Your profile, memberships and check-ins are deleted for good. '
          "Payments stay in the venues' records, without your name. This can't be undone.",
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    final done = await runAction(context, () => ref.read(authRepositoryProvider).deleteAccount());
    if (done && context.mounted) context.go(CoreRoutes.welcome);
  }
}

class _ProfileCard extends StatelessWidget {
  final Profile profile;

  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final initial = profile.displayName.characters.first.toUpperCase();
    return SectionCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: context.colors.primary,
            foregroundColor: context.colors.onPrimary,
            child: Text(initial, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.displayName, style: context.text.titleMedium),
                if (profile.email != null) Text(profile.email!, style: TextStyle(color: context.brand.muted)),
                if (profile.memberCode.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: StatusChip(label: 'Member code ${profile.memberCode}', color: context.colors.tertiary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto_rounded)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _dzongkhag;
  bool _loaded = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _fill(Profile p) {
    if (_loaded) return;
    _loaded = true;
    _name.text = p.fullName;
    _phone.text = p.phone ?? '';
    _dzongkhag = p.dzongkhag;
  }

  Future<void> _save(Profile p) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final phone = _phone.text.trim().isEmpty ? null : Validators.normalizePhone(_phone.text);
    final ok = await runAction(
      context,
      () => ref.read(profileRepositoryProvider).update(p.id, fullName: _name.text, phone: phone, dzongkhag: _dzongkhag),
      success: 'Profile saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(myProfileProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Edit profile',
      body: AsyncValueView<Profile?>(
        value: ref.watch(myProfileProvider),
        data: (p) {
          if (p == null) return const SizedBox.shrink();
          _fill(p);
          return Form(
            key: _form,
            child: ListView(
              padding: pagePadding(context),
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  validator: (v) => Validators.required(v, 'Your name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  validator: Validators.phone,
                ),
                const SizedBox(height: 14),
                DzongkhagField(value: _dzongkhag, required: false, onChanged: (v) => setState(() => _dzongkhag = v)),
                const SizedBox(height: 24),
                FilledButton(onPressed: _busy ? null : () => _save(p), child: const Text('Save')),
              ],
            ),
          );
        },
      ),
    );
  }
}
