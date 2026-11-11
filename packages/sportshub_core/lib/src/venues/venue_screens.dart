import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../auth/auth_repository.dart';
import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/launch.dart';
import '../utils/validators.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import '../widgets/loader.dart';
import 'venue.dart';
import 'venue_repository.dart';
import 'venue_widgets.dart';

/// 'Register your venue': the kinds the enabled modules serve. Gyms are
/// registered here; grounds on the ground booking website.
class RegisterVenueScreen extends ConsumerWidget {
  const RegisterVenueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(currentUserIdProvider) != null;
    return AppPage(
      title: 'Register your venue',
      body: AsyncValueView<List<SportsHubModule>>(
        value: ref.watch(enabledModulesProvider),
        onRetry: () => ref.invalidate(appModulesProvider),
        data: (modules) {
          final kinds = [for (final m in modules) ...m.venueKinds];
          return ListView(
            padding: pagePadding(context),
            children: [
              Text('What do you run?', style: context.text.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'The SportsHub team checks every venue before it goes live. You can add photos and '
                'prices while you wait.',
                style: TextStyle(color: context.brand.muted),
              ),
              const SizedBox(height: 16),
              if (kinds.isEmpty)
                const EmptyState(icon: Icons.storefront_rounded, title: 'Registration opens soon'),
              for (final kind in kinds)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: MenuTile(
                    icon: kind.icon,
                    title: kind.label,
                    subtitle: kind.externalRegisterUrl == null
                        ? kind.description
                        : '${kind.description}\nRegistered on our ground booking website',
                    trailing: kind.externalRegisterUrl == null ? null : const Icon(Icons.open_in_new_rounded, size: 20),
                    onTap: () {
                      if (kind.externalRegisterUrl != null) {
                        openExternal(context, kind.externalRegisterUrl!);
                      } else {
                        final form = CoreRoutes.registerVenueFor(kind.key);
                        context.push(signedIn ? form : CoreRoutes.signInFor(form));
                      }
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Registers a venue of [type], or edits venue [venueId] (and its photos).
class VenueFormScreen extends ConsumerStatefulWidget {
  final String? type;
  final String? venueId;

  const VenueFormScreen({super.key, this.type, this.venueId}) : assert(type != null || venueId != null);

  @override
  ConsumerState<VenueFormScreen> createState() => _VenueFormScreenState();
}

class _VenueFormScreenState extends ConsumerState<VenueFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _town = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _paymentInfo = TextEditingController();
  final _cancellation = TextEditingController();
  String? _dzongkhag;
  bool _filled = false;
  bool _busy = false;

  bool get _editing => widget.venueId != null;

  @override
  void dispose() {
    for (final c in [_name, _description, _town, _address, _phone, _whatsapp, _paymentInfo, _cancellation]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(Venue v) {
    if (_filled) return;
    _filled = true;
    _name.text = v.name;
    _description.text = v.description ?? '';
    _town.text = v.town ?? '';
    _address.text = v.address ?? '';
    _phone.text = v.phone ?? '';
    _whatsapp.text = v.whatsapp ?? '';
    _paymentInfo.text = v.paymentInfo ?? '';
    _cancellation.text = v.cancellationPolicy ?? '';
    _dzongkhag = v.dzongkhag;
  }

  VenueDraft _draft(String type) => VenueDraft(
        type: type,
        name: _name.text,
        description: _description.text,
        dzongkhag: _dzongkhag!,
        town: _town.text,
        address: _address.text,
        phone: Validators.normalizePhone(_phone.text),
        whatsapp: _whatsapp.text.trim().isEmpty ? null : Validators.normalizePhone(_whatsapp.text),
        paymentInfo: _paymentInfo.text,
        cancellationPolicy: _cancellation.text,
      );

  Future<void> _submit(String type) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(venueRepositoryProvider);
    String? newId;
    final ok = await runAction(
      context,
      () async {
        if (_editing) {
          await repo.update(widget.venueId!, _draft(type));
        } else {
          newId = await repo.register(_draft(type));
        }
      },
      success: _editing ? 'Saved' : 'Sent to the SportsHub team for verification',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    ref.invalidate(myVenuesProvider);
    if (_editing) {
      ref.invalidate(venueProvider(widget.venueId!));
      context.pop();
    } else {
      context.go(CoreRoutes.venueManageFor(newId!));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) return _page(context, type: widget.type!, venue: null);
    return AsyncValueView<VenueAccess?>(
      value: ref.watch(venueAccessProvider(widget.venueId!)),
      data: (access) {
        if (access == null || !access.can(VenuePermission.edit)) {
          return const AppPage(
            title: 'Edit venue',
            body: EmptyState(icon: Icons.lock_outline_rounded, title: "Your role here can't edit this venue"),
          );
        }
        _fill(access.venue);
        return _page(context, type: access.venue.type, venue: access.venue);
      },
    );
  }

  Widget _page(BuildContext context, {required String type, required Venue? venue}) {
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <SportsHubModule>[];
    final kind = [for (final m in modules) ...m.venueKinds].where((k) => k.key == type).firstOrNull;
    final label = kind?.label.toLowerCase() ?? 'venue';
    return AppPage(
      title: _editing ? 'Edit $label' : 'Register your $label',
      body: Form(
        key: _form,
        child: ListView(
          padding: pagePadding(context),
          children: [
            if (venue != null) ...[
              _PhotoEditor(venue: venue),
              const SizedBox(height: 20),
            ],
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name of the $label *'),
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the name' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 4,
              minLines: 2,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'About it', hintText: 'Equipment, opening hours, classes...'),
            ),
            const SizedBox(height: 6),
            DzongkhagField(value: _dzongkhag, onChanged: (v) => setState(() => _dzongkhag = v)),
            const SizedBox(height: 14),
            TextFormField(controller: _town, decoration: const InputDecoration(labelText: 'Town or area')),
            const SizedBox(height: 14),
            TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address or landmark')),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number *'),
              validator: (v) => Validators.phone(v, required: true),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _whatsapp,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'WhatsApp number'),
              validator: Validators.phone,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _paymentInfo,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'How to pay',
                hintText: 'e.g. mBoB account 200xxxxxx (Pema Wangmo), or cash at the front desk',
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _cancellation,
              maxLines: 3,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Cancellation and refund policy'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : () => _submit(type),
              child: Text(_editing ? 'Save' : 'Send for verification'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoEditor extends ConsumerStatefulWidget {
  final Venue venue;

  const _PhotoEditor({required this.venue});

  @override
  ConsumerState<_PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends ConsumerState<_PhotoEditor> {
  static const maxPhotos = 10;
  late List<String> _photos = [...widget.venue.photos];
  bool _busy = false;

  Future<void> _add() async {
    final photo = await pickPhoto(context);
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    final repo = ref.read(venueRepositoryProvider);
    await runAction(context, () async {
      final url = await repo.uploadPhoto(widget.venue.id, photo.bytes, contentType: photo.contentType);
      final next = [..._photos, url];
      await repo.setPhotos(widget.venue.id, next);
      if (mounted) setState(() => _photos = next);
    });
    if (mounted) setState(() => _busy = false);
    ref.invalidate(venueProvider(widget.venue.id));
  }

  Future<void> _remove(String url) async {
    final next = [..._photos]..remove(url);
    final ok = await runAction(context, () => ref.read(venueRepositoryProvider).setPhotos(widget.venue.id, next));
    if (ok && mounted) setState(() => _photos = next);
    ref.invalidate(venueProvider(widget.venue.id));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos', style: context.text.titleMedium),
        const SizedBox(height: 4),
        const FormHint('The first photo is the cover. Up to 10.'),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final url in _photos)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(url, width: 128, height: 96, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Remove photo',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () => _remove(url),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_photos.length < maxPhotos)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _busy ? null : _add,
                  child: Container(
                    width: 128,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.brand.glassBorder, width: 1.5),
                      color: context.brand.card,
                    ),
                    child: Center(
                      child: _busy
                          ? const SportsHubLoader(size: 36, semanticsLabel: 'Uploading')
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_a_photo_outlined, color: context.colors.primary),
                                const SizedBox(height: 4),
                                const Text('Add photo'),
                              ],
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The venues the signed-in user runs.
class MyVenuesScreen extends ConsumerWidget {
  const MyVenuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'Your venues',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(CoreRoutes.registerVenue),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Register a venue'),
      ),
      body: AsyncValueView<List<MyVenue>>(
        value: ref.watch(myVenuesProvider),
        onRetry: () => ref.invalidate(myVenuesProvider),
        data: (venues) => venues.isEmpty
            ? EmptyState(
                icon: Icons.storefront_rounded,
                title: "You don't run a venue yet",
                message: 'Register your gym and the SportsHub team will verify it.',
                actionLabel: 'Register your venue',
                onAction: () => context.push(CoreRoutes.registerVenue),
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(myVenuesProvider.future),
                child: ListView(
                  padding: pagePadding(context, bottom: 96),
                  children: [_MyVenuesTable(venues: venues)],
                ),
              ),
      ),
    );
  }
}

/// The venues they run, as a table: the venue, where, their role there, and
/// whether SportsHub has verified it; a row opens the venue.
class _MyVenuesTable extends ConsumerWidget {
  final List<MyVenue> venues;

  const _MyVenuesTable({required this.venues});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return DataGrid<MyVenue>(
      rows: venues,
      noun: 'venues',
      rowLabel: (v) => 'Open ${v.venue.name}',
      onRowTap: (v) => context.push(venueHomeRoute(ref.read(enabledModulesProvider).valueOrNull ?? const [], v.venue)),
      columns: [
        GridColumn(
          key: 'venue',
          label: 'Venue',
          flex: 4,
          sortBy: (v) => v.venue.name.toLowerCase(),
          cell: (context, v) {
            final tint = context.colors.tertiary;
            final photo = v.venue.coverPhoto;
            final icon = ColoredBox(color: tint.withValues(alpha: 0.12), child: Icon(Icons.storefront_rounded, color: tint, size: 22));
            return Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: photo == null
                        ? icon
                        : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => icon),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(v.venue.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                      Text(
                        [
                          if (!DataGrid.shows(context, 'place')) v.venue.place,
                          if (!DataGrid.shows(context, 'role')) 'You: ${v.roleName}',
                        ].join(' · ').ifEmpty(v.venue.type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: brand.muted, fontSize: 13),
                      ),
                      if (!DataGrid.shows(context, 'status'))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: VerificationChip(status: v.venue.verificationStatus),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        GridColumn(
          key: 'place',
          label: 'Where',
          flex: 3,
          showFrom: 700,
          sortBy: (v) => v.venue.place.toLowerCase(),
          cell: (context, v) => Text(v.venue.place, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'role',
          label: 'Your role',
          flex: 2,
          showFrom: 860,
          sortBy: (v) => v.roleName.toLowerCase(),
          cell: (context, v) => Text(v.roleName, style: TextStyle(color: brand.body, fontWeight: FontWeight.w600)),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 136,
          showFrom: 520,
          sortBy: (v) => v.venue.verificationStatus,
          cell: (context, v) => VerificationChip(status: v.venue.verificationStatus),
        ),
        GridColumn(
          key: 'open',
          label: '',
          width: 40,
          alignEnd: true,
          cell: (context, v) => Icon(Icons.chevron_right_rounded, color: brand.muted),
        ),
      ],
    );
  }
}

extension on String {
  /// This, or [other] when it's empty.
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Running one venue: its status, the module's pages for it (members,
/// check-in...), and the core's (details, photos, staff).
class VenueManageScreen extends ConsumerWidget {
  final String venueId;

  const VenueManageScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(venueAccessProvider(venueId));
    return AppPage(
      title: access.valueOrNull?.venue.name ?? 'Manage',
      body: AsyncValueView<VenueAccess?>(
        value: access,
        onRetry: () => ref.invalidate(myVenuesProvider),
        data: (a) {
          if (a == null) {
            return const EmptyState(icon: Icons.lock_outline_rounded, title: "You don't run this venue");
          }
          final venue = a.venue;
          final module = ref.watch(moduleForVenueTypeProvider(venue.type));
          // A module with its own console (a gym's dashboard) runs the venue
          // there: this page would only repeat it.
          if (module?.managerHomeRoute(venue) case final home?) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) context.go(home);
            });
            return const Center(child: SportsHubLoader());
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myVenuesProvider);
              ref.invalidate(venueProvider(venueId));
            },
            child: ListView(
              padding: pagePadding(context),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(venue.name, style: context.text.titleLarge)),
                          VerificationChip(status: venue.verificationStatus),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${venue.place} · You: ${a.roleName}', style: TextStyle(color: context.brand.muted)),
                      if (venue.verificationStatus == VerificationStatus.pending) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'The SportsHub team will check your details and let you know. Meanwhile, add photos '
                          'and set up your plans so you are ready to go live.',
                        ),
                      ],
                      if (venue.verificationStatus == VerificationStatus.rejected) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Sent back by the SportsHub team${venue.verificationNote == null ? '.' : ': ${venue.verificationNote}'}',
                          style: TextStyle(color: context.brand.danger),
                        ),
                        const SizedBox(height: 4),
                        const Text('Edit the details and save to send it again.'),
                      ],
                    ],
                  ),
                ),
                if (module == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('This part of SportsHub is turned off for now.'),
                  )
                else ...[
                  if (module.buildManagerSection(context, venue, a) case final section?) ...[
                    const SizedBox(height: 12),
                    section,
                  ],
                  SectionTitle(module.name),
                  for (final item in module.managerMenuItems(venue, a))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MenuTile(icon: item.icon, title: item.title, subtitle: item.subtitle, onTap: () => item.open(context)),
                    ),
                ],
                const SectionTitle('Venue'),
                if (a.can(VenuePermission.edit))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: MenuTile(
                      icon: Icons.edit_note_rounded,
                      title: 'Details and photos',
                      subtitle: 'Name, contact, how to pay, policy',
                      onTap: () => context.push(CoreRoutes.editVenueFor(venue.id)),
                    ),
                  ),
                MenuTile(
                  icon: Icons.badge_outlined,
                  title: 'Staff',
                  subtitle: a.can(VenuePermission.staff) ? 'Add staff, make their accounts, choose their roles' : 'Who runs this venue',
                  onTap: () => context.push(CoreRoutes.venueStaffFor(venue.id)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

