import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/registered_member.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';
import '../widgets/member_card.dart';
import '../widgets/member_photo.dart';
import '../widgets/package_fields.dart';

/// [member]'s memberships at the gym, newest first.
List<GymSubscription> membershipsOf(Iterable<GymSubscription> all, String gymMemberId) =>
    all.where((s) => s.gymMemberId == gymMemberId).toList()..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

/// The last day their packages (renewals included) cover, if any is
/// current or still to start.
DateTime? paidUntil(Iterable<GymSubscription> subs, DateTime today) {
  DateTime? until;
  for (final s in subs) {
    if ((s.isCurrentOn(today) || s.isUpcomingOn(today)) && (until == null || s.endDate!.isAfter(until))) until = s.endDate;
  }
  return until;
}

/// Their package in a line: 'Gym · until 7 Feb 2027', 'Gym from 1 Dec',
/// 'Gym ended 3 Oct', 'No package yet'.
String packageLine(List<GymSubscription> subs, DateTime today) {
  final current = subs.where((s) => s.isCurrentOn(today)).firstOrNull;
  final until = paidUntil(subs, today);
  if (current != null) return '${current.planName} · until ${formatDate(until!)}';
  final upcoming = subs.where((s) => s.isUpcomingOn(today)).firstOrNull;
  if (upcoming != null) return '${upcoming.planName} · from ${formatDate(upcoming.startDate!)}';
  final ended = subs.where((s) => s.endDate != null).toList()..sort((a, b) => b.endDate!.compareTo(a.endDate!));
  if (ended.isNotEmpty) return '${ended.first.planName} · ended ${formatDate(ended.first.endDate!)}';
  return 'No package yet';
}

/// Their standing as a chip.
class StandingChip extends StatelessWidget {
  final MemberStanding standing;
  final int? daysLeft;

  const StandingChip({super.key, required this.standing, this.daysLeft});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return switch (standing) {
      MemberStanding.active => StatusChip(
          label: daysLeft == null ? 'Active' : (daysLeft == 1 ? 'Last day' : '$daysLeft days left'),
          color: (daysLeft ?? 99) <= 7 ? brand.warning : brand.success,
          icon: Icons.check_circle_rounded,
        ),
      MemberStanding.upcoming => StatusChip(label: 'Starts soon', color: context.colors.tertiary, icon: Icons.event_rounded),
      MemberStanding.ended => StatusChip(label: 'Ended', color: brand.danger, icon: Icons.history_rounded),
      MemberStanding.none => StatusChip(label: 'No package', color: brand.muted),
    };
  }
}

/// What they told the desk: email, birthday, blood group, work, address,
/// date of joining, emergency contact; their phone too with [withPhone].
class MemberDetailsCard extends StatelessWidget {
  final GymMember member;
  final bool withPhone;

  const MemberDetailsCard({super.key, required this.member, this.withPhone = false});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final today = BhutanTime.today();
    String? age() {
      final dob = m.dateOfBirth;
      if (dob == null) return null;
      var years = today.year - dob.year;
      if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) years--;
      return '${formatDate(dob)} (age $years)';
    }

    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: ResponsiveGrid(
        minItemWidth: 260,
        maxColumns: 2,
        spacing: 16,
        runSpacing: 2,
        equalHeight: false,
        children: [
          if (withPhone) InfoRow(icon: Icons.call_outlined, text: m.phone),
          if (m.email != null) InfoRow(icon: Icons.mail_outline_rounded, text: m.email!),
          if (age() != null) InfoRow(icon: Icons.cake_outlined, text: age()!),
          if (m.bloodGroup != null) InfoRow(icon: Icons.bloodtype_outlined, text: 'Blood group ${m.bloodGroup}'),
          if (m.occupation != null) InfoRow(icon: Icons.work_outline_rounded, text: m.occupation!),
          if (m.placeName != null) InfoRow(icon: Icons.place_outlined, text: m.placeName!),
          InfoRow(icon: Icons.event_available_outlined, text: 'Joined ${formatDate(m.joinedOn)}'),
          if (m.emergencyContactName != null || m.emergencyContactPhone != null)
            InfoRow(
              icon: Icons.contact_emergency_outlined,
              text: 'Emergency: ${[m.emergencyContactName, m.emergencyContactPhone].whereType<String>().join(' · ')}',
            ),
        ],
      ),
    );
  }
}

/// Their medical issues, for the desk and trainers to see first.
class MedicalNotice extends StatelessWidget {
  final String notes;

  const MedicalNotice(this.notes, {super.key});

  @override
  Widget build(BuildContext context) {
    final warning = context.brand.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.medical_information_outlined, color: warning),
          const SizedBox(width: 12),
          Expanded(child: Text(notes)),
        ],
      ),
    );
  }
}

enum _Filter {
  all('All'),
  active('Active'),
  ending('Ending in 7 days'),
  ended('Ended'),
  none('No package');

  const _Filter(this.label);
  final String label;
}

enum _Sort {
  name('Name, A to Z'),
  expiry('Expiry date, soonest first'),
  newest('Newest first');

  const _Sort(this.label);
  final String label;
}

/// Whether [subs] (one member's) pass [filter] on [today].
bool _passes(_Filter filter, List<GymSubscription> subs, DateTime today) {
  final standing = standingOf(subs, today);
  return switch (filter) {
    _Filter.all => true,
    _Filter.active => standing == MemberStanding.active || standing == MemberStanding.upcoming,
    _Filter.ending => standing == MemberStanding.active &&
        !subs.any((s) => s.isUpcomingOn(today)) &&
        BhutanTime.daysBetween(today, paidUntil(subs, today)!) < 7,
    _Filter.ended => standing == MemberStanding.ended,
    _Filter.none => standing == MemberStanding.none,
  };
}

// ─── The register ─────────────────────────────────────────────────────────

/// Everyone registered at the gym's front desk: found by name, phone or
/// member code; filtered by where their package stands (with how many in
/// each); sorted by name, expiry or joining; as a table on a computer and
/// cards on a phone.
class MembersScreen extends ConsumerStatefulWidget {
  final String venueId;

  const MembersScreen({super.key, required this.venueId});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.name;
  String _search = '';

  /// Cards even where a table fits.
  bool _cards = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.venueId;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return GymStaffPage(
      venueId: id,
      title: 'Members',
      permission: GymPermission.members,
      builder: (context, access) {
        final members = ref.watch(gymMembersProvider(id));
        final subs = ref.watch(gymSubscriptionsProvider(id)).valueOrNull ?? const <GymSubscription>[];
        final today = BhutanTime.today();
        final canRegister = access.can(GymPermission.register);
        return AppPage(
          title: 'Members',
          actions: [
            if (canRegister && wide)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: OutlinedButton.icon(
                  onPressed: () => context.go(GymRoutes.registerMemberFor(id)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                  label: const Text('Register member'),
                ),
              ),
          ],
          floatingActionButton: canRegister && !wide
              ? FloatingActionButton.extended(
                  onPressed: () => context.go(GymRoutes.registerMemberFor(id)),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Register member'),
                )
              : null,
          body: AsyncValueView<List<GymMember>>(
            value: members,
            onRetry: () => ref.invalidate(gymMembersProvider(id)),
            data: (all) {
              final everyone = [for (final m in all) (member: m, subs: membershipsOf(subs, m.id))];
              final counts = {
                for (final f in _Filter.values) f: everyone.where((r) => _passes(f, r.subs, today)).length,
              };
              final rows = everyone.where((r) => _matches(r.member) && _passes(_filter, r.subs, today)).toList();
              rows.sort((a, b) => switch (_sort) {
                    _Sort.name => a.member.fullName.toLowerCase().compareTo(b.member.fullName.toLowerCase()),
                    _Sort.newest => b.member.joinedOn.compareTo(a.member.joinedOn),
                    _Sort.expiry => (paidUntil(a.subs, today) ?? DateTime(9999))
                        .compareTo(paidUntil(b.subs, today) ?? DateTime(9999)),
                  });
              return RefreshIndicator(
                onRefresh: () async => refreshGym(ref, id),
                child: ListView(
                  padding: pagePadding(context, bottom: 96),
                  children: [
                    if (all.isEmpty)
                      EmptyState(
                        icon: Icons.groups_rounded,
                        title: 'Register your first member',
                        message: 'Register members at the front desk: their details, photo and package. '
                            'They get a QR card to show when they come in.',
                        actionLabel: canRegister ? 'Register a member' : null,
                        onAction: () => context.go(GymRoutes.registerMemberFor(id)),
                      )
                    else ...[
                      LayoutBuilder(builder: (context, c) => _toolbar(context, wide: c.maxWidth >= 760)),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final f in _Filter.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text('${f.label}  ${counts[f]}'),
                                  selected: _filter == f,
                                  onSelected: (_) => setState(() => _filter = f),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              _search.isEmpty ? 'Nobody here.' : 'Nobody matches "$_search".',
                              style: TextStyle(color: context.brand.muted),
                            ),
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, c) => c.maxWidth >= 1000 && !_cards
                              ? _MembersTable(
                                  rows: rows,
                                  today: today,
                                  onOpen: (m) => context.go(GymRoutes.memberFor(id, m.id)),
                                )
                              : ResponsiveGrid(
                                  minItemWidth: 360,
                                  maxColumns: 3,
                                  children: staggered([
                                    for (final r in rows)
                                      _MemberTile(
                                        member: r.member,
                                        subs: r.subs,
                                        today: today,
                                        onTap: () => context.go(GymRoutes.memberFor(id, r.member.id)),
                                      ),
                                  ], step: const Duration(milliseconds: 30)),
                                ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// Search, sort, and (on a computer) table or cards.
  Widget _toolbar(BuildContext context, {required bool wide}) {
    final search = TextField(
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: 'Search by name, phone or member code',
        suffixIcon: _search.isEmpty ? null : const Icon(Icons.manage_search_rounded),
      ),
      onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
    );
    final sort = PopupMenuButton<_Sort>(
      tooltip: 'Sort',
      initialValue: _sort,
      onSelected: (s) => setState(() => _sort = s),
      itemBuilder: (_) => [for (final s in _Sort.values) CheckedPopupMenuItem(value: s, checked: s == _sort, child: Text(s.label))],
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.brand.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.brand.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 20),
            const SizedBox(width: 8),
            Text(wide ? _sort.label : 'Sort', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
    final view = SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: false, icon: Icon(Icons.table_rows_rounded), tooltip: 'Table'),
        ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded), tooltip: 'Cards'),
      ],
      selected: {_cards},
      onSelectionChanged: (v) => setState(() => _cards = v.first),
    );
    return Row(
      children: [
        Expanded(child: search),
        const SizedBox(width: 10),
        sort,
        if (MediaQuery.sizeOf(context).width >= 1300) ...[const SizedBox(width: 10), view],
      ],
    );
  }

  bool _matches(GymMember m) {
    if (_search.isEmpty) return true;
    final digits = _search.replaceAll(RegExp(r'\D'), '');
    return m.fullName.toLowerCase().contains(_search) ||
        m.code.toLowerCase().contains(_search) ||
        (digits.isNotEmpty && m.phone.replaceAll(RegExp(r'\D'), '').contains(digits));
  }
}

/// The register as a table: who (photo, name, code), phone, package, expiry
/// date, standing, and WhatsApp; a row opens the member.
class _MembersTable extends StatelessWidget {
  final List<({GymMember member, List<GymSubscription> subs})> rows;
  final DateTime today;
  final ValueChanged<GymMember> onOpen;

  const _MembersTable({required this.rows, required this.today, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final muted = context.brand.muted;
    TextStyle head = TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: 0.3);
    Widget row(List<Widget> cells, {bool header = false}) => Row(
          children: [
            Expanded(flex: 4, child: cells[0]),
            Expanded(flex: 2, child: cells[1]),
            Expanded(flex: 3, child: cells[2]),
            Expanded(flex: 2, child: cells[3]),
            Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: cells[4])),
            SizedBox(width: 96, child: Align(alignment: Alignment.centerRight, child: cells[5])),
          ],
        );
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
            child: row([
              Text('MEMBER', style: head),
              Text('PHONE', style: head),
              Text('PACKAGE', style: head),
              Text('EXPIRY DATE', style: head),
              Text('STATUS', style: head),
              const SizedBox(),
            ]),
          ),
          const Divider(height: 1),
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18),
            _TableRow(
              onTap: () => onOpen(r.member),
              child: row([
                Row(
                  children: [
                    MemberPhoto(path: r.member.photoPath, name: r.member.fullName, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.member.fullName,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(r.member.code, style: TextStyle(color: muted, fontSize: 12.5, letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(r.member.phone, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  r.subs.firstWhere((s) => s.isCurrentOn(today), orElse: () => r.subs.isEmpty ? _none : r.subs.first).planName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(() {
                  final until = paidUntil(r.subs, today);
                  if (until != null) return formatDate(until);
                  final ended = r.subs.where((s) => s.endDate != null).map((s) => s.endDate!).fold<DateTime?>(
                      null, (a, b) => a == null || b.isAfter(a) ? b : a);
                  return ended == null ? '—' : formatDate(ended);
                }(), style: const TextStyle(fontWeight: FontWeight.w600)),
                StandingChip(
                  standing: standingOf(r.subs, today),
                  daysLeft: paidUntil(r.subs, today) == null ? null : BhutanTime.daysBetween(today, paidUntil(r.subs, today)!) + 1,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'WhatsApp ${firstName(r.member.fullName)}',
                      icon: const Icon(Icons.chat_outlined, size: 20),
                      onPressed: () => openWhatsApp(context, r.member.phone),
                    ),
                    Icon(Icons.chevron_right_rounded, color: muted),
                  ],
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  static final _none = GymSubscription(
    id: '',
    venueId: '',
    memberId: '',
    planName: '—',
    durationDays: 1,
    price: 0,
    status: SubscriptionStatus.cancelled,
    requestedAt: DateTime(2000),
  );
}

/// A row that lights up under the mouse and opens on a tap.
class _TableRow extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TableRow({required this.child, required this.onTap});

  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        color: _hover ? context.colors.tertiary.withValues(alpha: 0.05) : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(padding: const EdgeInsets.fromLTRB(18, 10, 12, 10), child: widget.child),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final GymMember member;
  final List<GymSubscription> subs;
  final DateTime today;
  final VoidCallback onTap;

  const _MemberTile({required this.member, required this.subs, required this.today, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final standing = standingOf(subs, today);
    final until = paidUntil(subs, today);
    return SectionCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          MemberPhoto(path: member.photoPath, name: member.fullName, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5), overflow: TextOverflow.ellipsis),
                Text('${member.code} · ${member.phone}', style: TextStyle(color: context.brand.muted)),
                const SizedBox(height: 2),
                Text(packageLine(subs, today), style: context.text.bodySmall, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StandingChip(standing: standing, daysLeft: until == null ? null : BhutanTime.daysBetween(today, until) + 1),
        ],
      ),
    );
  }
}

// ─── Registering, and changing details ────────────────────────────────────

/// The front desk's registration form (the client's: name, phone, email,
/// dzongkhag and village, occupation, emergency contact, blood group, date of
/// joining, package and months, expiry, date of birth, medical issues), the
/// member's photo from the webcam, and the package sold. With [memberId], it
/// changes a registered member's details instead.
class RegisterMemberScreen extends ConsumerWidget {
  final String venueId;
  final String? memberId;

  const RegisterMemberScreen({super.key, required this.venueId, this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = memberId != null;
    return GymStaffPage(
      venueId: venueId,
      title: editing ? 'Edit member' : 'Register member',
      permission: GymPermission.register,
      builder: (context, access) {
        if (!editing) return _MemberForm(venueId: venueId, access: access);
        return AsyncValueView<GymMember?>(
          value: ref.watch(gymMemberProvider(memberId!)),
          onRetry: () => ref.invalidate(gymMemberProvider(memberId!)),
          data: (m) => m == null
              ? const AppPage(title: 'Edit member', body: EmptyState(icon: Icons.person_off_outlined, title: 'This member is not registered here'))
              : _MemberForm(venueId: venueId, access: access, member: m),
        );
      },
    );
  }
}

class _MemberForm extends ConsumerStatefulWidget {
  final String venueId;
  final VenueAccess access;
  final GymMember? member;

  const _MemberForm({required this.venueId, required this.access, this.member});

  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  final _form = GlobalKey<FormState>();

  /// Each section of the form, to scroll to it from the summary.
  final _sectionKeys = List.generate(5, (_) => GlobalKey());
  late final MemberDetails? _old = widget.member?.details;
  late final _name = TextEditingController(text: _old?.fullName ?? '');
  late final _phone = TextEditingController(text: _old?.phone ?? '');
  late final _email = TextEditingController(text: _old?.email ?? '');
  late final _occupation = TextEditingController(text: _old?.occupation ?? '');
  late final _contactName = TextEditingController(text: _old?.emergencyContactName ?? '');
  late final _contactPhone = TextEditingController(text: _old?.emergencyContactPhone ?? '');
  late final _medical = TextEditingController(text: _old?.medicalNotes ?? '');
  late DateTime? _dob = _old?.dateOfBirth;
  late DateTime _joined = _old?.joinedOn ?? BhutanTime.today();
  late String? _bloodGroup = _old?.bloodGroup;
  late LocationSelection _place = _old?.place ?? LocationSelection.empty;
  late bool _sell = widget.member == null && widget.access.can(GymPermission.payments);
  PackageSale? _sale;
  PickedPhoto? _photo;
  bool _saving = false;

  bool get _editing => widget.member != null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _occupation, _contactName, _contactPhone, _medical]) {
      c.dispose();
    }
    super.dispose();
  }

  MemberDetails get _details => MemberDetails(
        fullName: _name.text,
        phone: _phone.text,
        email: _email.text,
        dateOfBirth: _dob,
        bloodGroup: _bloodGroup,
        occupation: _occupation.text,
        place: _place,
        emergencyContactName: _contactName.text,
        emergencyContactPhone: _contactPhone.text,
        medicalNotes: _medical.text,
        joinedOn: _joined,
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_sell && _sale == null) return;
    setState(() => _saving = true);
    final repo = ref.read(gymRepositoryProvider);
    String? id;
    String? photoProblem;
    final ok = await runAction(context, () async {
      if (_editing) {
        await repo.updateMember(widget.member!.id, _details);
        id = widget.member!.id;
      } else {
        id = await repo.registerMember(widget.venueId, _details, sale: _sell ? _sale : null);
      }
      if (_photo != null) {
        try {
          await repo.setMemberPhoto(
            venueId: widget.venueId,
            memberId: id!,
            bytes: _photo!.bytes,
            contentType: _photo!.contentType,
            oldPath: widget.member?.photoPath,
          );
        } catch (_) {
          photoProblem = "Saved, but the photo didn't upload. Add it again with Edit details.";
        }
      }
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok || id == null) return;
    refreshGym(ref, widget.venueId);
    ref.invalidate(gymMemberProvider(id!));
    if (photoProblem != null || _editing) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(photoProblem ?? 'Saved')));
    }
    // A new member: the page that says so, with their QR card to send.
    context.go(_editing ? GymRoutes.memberFor(widget.venueId, id!) : GymRoutes.memberRegisteredFor(widget.venueId, id!));
  }

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final canSell = widget.access.can(GymPermission.payments);
    Widget fields(List<Widget> children) =>
        ResponsiveGrid(minItemWidth: 260, maxColumns: 3, spacing: 14, runSpacing: 14, equalHeight: false, children: children);

    void changed(_) => setState(() {});
    final personal = fields([
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.badge_outlined)),
        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter their name' : null,
        onChanged: changed,
      ),
      TextFormField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Phone *', hintText: '17123456', prefixIcon: Icon(Icons.call_outlined)),
        validator: (v) => Validators.phone(v, required: true),
        onChanged: changed,
      ),
      TextFormField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        validator: (v) => (v ?? '').trim().isEmpty ? null : Validators.email(v),
        onChanged: changed,
      ),
      DateField(
        label: 'Date of birth',
        value: _dob,
        clearable: true,
        firstDate: DateTime(1920),
        lastDate: today,
        onChanged: (d) => setState(() => _dob = d),
      ),
      DropdownButtonFormField<String>(
        initialValue: _bloodGroup,
        decoration: const InputDecoration(labelText: 'Blood group', prefixIcon: Icon(Icons.bloodtype_outlined)),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('Not known')),
          for (final g in bloodGroups) DropdownMenuItem(value: g, child: Text(g)),
        ],
        onChanged: (g) => setState(() => _bloodGroup = g),
      ),
      TextFormField(
        controller: _occupation,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Occupation', prefixIcon: Icon(Icons.work_outline_rounded)),
        onChanged: changed,
      ),
      DateField(
        label: 'Date of joining',
        value: _joined,
        required: true,
        firstDate: today.subtract(const Duration(days: 3650)),
        lastDate: today.add(const Duration(days: 60)),
        onChanged: (d) => setState(() => _joined = d ?? today),
      ),
    ]);

    final address = LocationFields(value: _place, inRow: true, onChanged: (v) => setState(() => _place = v));

    final emergencyAndHealth = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        fields([
          TextFormField(
            controller: _contactName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Emergency contact name', prefixIcon: Icon(Icons.contact_emergency_outlined)),
            onChanged: changed,
          ),
          TextFormField(
            controller: _contactPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Emergency contact number', prefixIcon: Icon(Icons.phone_in_talk_outlined)),
            validator: Validators.phone,
            onChanged: changed,
          ),
        ]),
        const SizedBox(height: 14),
        TextFormField(
          controller: _medical,
          minLines: 2,
          maxLines: 5,
          maxLength: 1000,
          onChanged: changed,
          decoration: const InputDecoration(
            labelText: 'Any medical issues',
            hintText: 'Asthma, a heart condition, injuries... Trainers and the desk see this.',
            prefixIcon: Icon(Icons.medical_information_outlined),
          ),
        ),
      ],
    );

    final package = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sell a package now', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(canSell
              ? 'From the date of joining. Leave it off to register them first.'
              : "Your role can't take payments: someone who can adds their package from their page."),
          value: _sell,
          onChanged: canSell ? (v) => setState(() => _sell = v) : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _sell
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: PackageFields(venueId: widget.venueId, start: _joined, onChanged: (s) => setState(() => _sale = s)),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );

    final photo = Column(
      children: [
        MemberPhotoField(
          picked: _photo,
          currentPath: widget.member?.photoPath,
          name: _name.text,
          onChanged: (p) => setState(() => _photo = p),
        ),
        const SizedBox(height: 10),
        const FormHint('The desk sees it when they check in, so they know it is them.'),
      ],
    );

    // Where the form stands: what's done in each section, and how far along.
    final hasPhoto = _photo != null || widget.member?.photoPath != null;
    final named = _name.text.trim().length >= 2;
    final phoned = Validators.phone(_phone.text, required: true) == null;
    final done = [
      hasPhoto,
      named && phoned,
      _place.dzongkhagId != null,
      _contactName.text.trim().isNotEmpty || _contactPhone.text.trim().isNotEmpty,
      !_sell || _sale != null,
    ];
    final filled = [
      hasPhoto, named, phoned, _email.text.trim().isNotEmpty, _dob != null, _bloodGroup != null,
      _occupation.text.trim().isNotEmpty, _place.dzongkhagId != null, _contactName.text.trim().isNotEmpty,
      _contactPhone.text.trim().isNotEmpty, _medical.text.trim().isNotEmpty, if (_sell) _sale != null,
    ];
    final progress = filled.where((f) => f).length / filled.length;
    final ready = named && phoned && (!_sell || _sale != null);

    final sections = [
      (Icons.photo_camera_outlined, 'Photo', 'Snap it with the webcam, or upload one', photo),
      (Icons.person_outline_rounded, 'Personal details', 'Who they are and how to reach them', personal),
      (Icons.place_outlined, 'Address', 'Dzongkhag, gewog and village', address),
      (Icons.health_and_safety_outlined, 'Emergency contact & health', 'Who to call, and what the desk should know', emergencyAndHealth),
      if (!_editing) (Icons.sell_outlined, 'Package', 'What they signed up for; the expiry date is worked out', package),
    ];

    final cancel = TextButton(
      onPressed: _saving
          ? null
          : () => context.go(_editing ? GymRoutes.memberFor(widget.venueId, widget.member!.id) : GymRoutes.membersFor(widget.venueId)),
      child: const Text('Cancel'),
    );
    final submit = FilledButton.icon(
      onPressed: _saving ? null : _save,
      icon: _saving
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_editing ? Icons.save_outlined : Icons.how_to_reg_rounded),
      label: Text(_editing ? 'Save changes' : 'Register member', overflow: TextOverflow.ellipsis),
    );

    final wide = MediaQuery.sizeOf(context).width >= 1280;
    final form = ListView(
      padding: pagePadding(context, bottom: wide ? 40 : 110),
      children: [
        for (final (i, (icon, title, subtitle, child)) in sections.indexed)
          FadeSlideIn(
            key: _sectionKeys[i],
            delay: Duration(milliseconds: 50 * i),
            child: _FormSection(number: i + 1, icon: icon, title: title, subtitle: subtitle, done: done[i], child: child),
          ),
      ],
    );

    return AppPage(
      title: _editing ? 'Edit ${widget.member!.fullName}' : 'Register a member',
      bottomBar: wide
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ready ? 'Ready to save' : 'Name and phone are needed${_sell ? ', and the package' : ''}',
                      maxLines: 2,
                      style: TextStyle(color: ready ? context.brand.success : context.brand.muted, fontWeight: FontWeight.w600),
                    ),
                  ),
                  cancel,
                  const SizedBox(width: 8),
                  Flexible(child: submit),
                ],
              ),
            ),
      body: Form(
        key: _form,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: form),
                  SizedBox(
                    width: 360,
                    child: SingleChildScrollView(
                      padding: pagePadding(context, horizontal: 0).copyWith(right: 28),
                      child: _RegisterSummary(
                        name: _name.text,
                        phone: _phone.text,
                        photoPath: widget.member?.photoPath,
                        photo: _photo?.bytes,
                        joined: _joined,
                        sale: _sell ? _sale : null,
                        selling: _sell,
                        progress: progress,
                        sections: [for (final (i, s) in sections.indexed) (title: s.$2, done: done[i])],
                        onSection: (i) => Scrollable.ensureVisible(
                          _sectionKeys[i].currentContext!,
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOutCubic,
                          alignment: 0.05,
                        ),
                        actions: [SizedBox(width: double.infinity, child: submit), const SizedBox(height: 6), cancel],
                      ),
                    ),
                  ),
                ],
              )
            : form,
      ),
    );
  }
}

/// A numbered part of the registration form: its number (a tick once it's
/// done), title, what it's for, and its fields on a card.
class _FormSection extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final Widget child;

  const _FormSection({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final success = context.brand.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: SectionCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? success : BrandColors.orange.withValues(alpha: 0.12),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: done
                        ? const Icon(Icons.check_rounded, key: ValueKey('done'), color: Colors.white, size: 20)
                        : Text('$number',
                            key: const ValueKey('n'),
                            style: const TextStyle(color: BrandColors.orange, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleMedium),
                      Text(subtitle, style: TextStyle(color: context.brand.muted, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(icon, color: context.brand.muted),
              ],
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

/// Beside the form on a computer: the member as they'll be registered (photo,
/// name, package, expiry date, amount), how complete the form is, a way to
/// each section, and saving.
class _RegisterSummary extends StatelessWidget {
  final String name;
  final String phone;
  final String? photoPath;
  final Uint8List? photo;
  final DateTime joined;
  final PackageSale? sale;
  final bool selling;
  final double progress;
  final List<({String title, bool done})> sections;
  final ValueChanged<int> onSection;
  final List<Widget> actions;

  const _RegisterSummary({
    required this.name,
    required this.phone,
    required this.photoPath,
    required this.photo,
    required this.joined,
    required this.sale,
    required this.selling,
    required this.progress,
    required this.sections,
    required this.onSection,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final muted = context.brand.muted;
    final sale = this.sale;
    Widget fact(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(color: muted))),
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              ),
            ],
          ),
        );
    return SectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Summary', style: context.text.titleMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              MemberPhoto(path: photoPath, name: name, bytes: photo, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.trim().isEmpty ? 'New member' : name.trim(),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(phone.trim().isEmpty ? 'No phone yet' : phone.trim(), style: TextStyle(color: muted)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          fact('Joining', formatDate(joined)),
          if (!selling)
            fact('Package', 'Not now')
          else if (sale == null)
            fact('Package', 'Choose one', color: context.brand.warning)
          else ...[
            fact('Package', '${sale.plan.name} · ${sale.months == 1 ? '1 month' : '${sale.months} months'}'),
            fact('Expiry date', formatDate(packageEnd(joined, sale.months)), color: context.brand.success),
            fact('Amount', sale.amount == 0 ? 'Free' : '${formatNu(sale.amount)}${sale.method == null ? '' : ' · ${sale.method!.label}'}'),
          ],
          const Divider(height: 28),
          Row(
            children: [
              Expanded(child: Text('Form complete', style: TextStyle(color: muted))),
              Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: BrandColors.orange,
                backgroundColor: BrandColors.orange.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final (i, s) in sections.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSection(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(
                  children: [
                    Icon(s.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 18, color: s.done ? context.brand.success : muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.title)),
                    Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          ...actions,
        ],
      ),
    );
  }
}

// ─── One member ──────────────────────────────────────────────────────────

/// A registered member: who they are, their package (and renewing it), their
/// QR card to send on WhatsApp, their details, memberships and visits.
class GymMemberScreen extends ConsumerWidget {
  final String venueId;
  final String memberId;

  const GymMemberScreen({super.key, required this.venueId, required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Member',
      permission: GymPermission.members,
      builder: (context, access) => AsyncValueView<GymMember?>(
        value: ref.watch(gymMemberProvider(memberId)),
        onRetry: () => ref.invalidate(gymMemberProvider(memberId)),
        data: (m) => m == null || m.venueId != venueId
            ? const AppPage(title: 'Member', body: EmptyState(icon: Icons.person_off_outlined, title: 'This member is not registered here'))
            : _MemberPage(member: m, access: access),
      ),
    );
  }
}

class _MemberPage extends ConsumerStatefulWidget {
  final GymMember member;
  final VenueAccess access;

  const _MemberPage({required this.member, required this.access});

  @override
  ConsumerState<_MemberPage> createState() => _MemberPageState();
}

class _MemberPageState extends ConsumerState<_MemberPage> {
  GymMember get m => widget.member;
  String get _venueId => widget.access.venue.id;

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final all = ref.watch(gymSubscriptionsProvider(_venueId)).valueOrNull ?? const <GymSubscription>[];
    final subs = membershipsOf(all, m.id);
    final standing = standingOf(subs, today);
    final until = paidUntil(subs, today);
    final visits = ref.watch(gymMemberCheckInsProvider(m.id)).valueOrNull ?? const <GymCheckIn>[];
    final a = widget.access;

    final header = SectionCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MemberPhoto(path: m.photoPath, name: m.fullName, size: 96),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.fullName, style: context.text.headlineSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusChip(label: 'Member code ${m.code}', color: context.colors.tertiary),
                    StandingChip(standing: standing, daysLeft: until == null ? null : BhutanTime.daysBetween(today, until) + 1),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => callPhone(context, m.phone),
                      icon: const Icon(Icons.call_outlined),
                      label: Text(m.phone),
                    ),
                    if (a.can(GymPermission.register))
                      OutlinedButton.icon(
                        onPressed: () => context.go(GymRoutes.editMemberFor(_venueId, m.id)),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit details'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final package = SectionCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(packageLine(subs, today), style: context.text.titleMedium)),
              if (a.can(GymPermission.payments))
                FilledButton.icon(
                  onPressed: () => _renew(context),
                  icon: const Icon(Icons.autorenew_rounded),
                  label: Text(standing == MemberStanding.none ? 'Sell a package' : 'Renew'),
                ),
            ],
          ),
          if (subs.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final s in subs.take(6))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${s.planName} · ${s.price == 0 ? 'Free' : formatNu(s.price)}'),
                subtitle: Text(s.startDate == null ? 'Not started' : '${formatDate(s.startDate!)} to ${formatDate(s.endDate!)}'),
                trailing: SubscriptionStatusChip(subscription: s),
              ),
          ],
        ],
      ),
    );

    final details = MemberDetailsCard(member: m);
    final medical = m.medicalNotes == null ? null : MedicalNotice(m.medicalNotes!);

    final card = MemberCardPanel(
      gymName: widget.access.venue.name,
      member: m,
      until: until,
      noPackage: packageLine(subs, today),
      canReissue: a.can(GymPermission.register),
    );

    return AppPage(
      title: m.fullName,
      body: RefreshIndicator(
        onRefresh: () async {
          refreshGym(ref, _venueId);
          ref.invalidate(gymMemberProvider(m.id));
          ref.invalidate(gymMemberCheckInsProvider(m.id));
        },
        child: ListView(
          padding: pagePadding(context),
          children: [
            ResponsiveColumns(
              breakpoint: 1000,
              flex: (3, 2),
              first: [
                header,
                if (medical != null) ...[const SizedBox(height: 12), medical],
                const SectionTitle('Package'),
                package,
                const SectionTitle('Details'),
                details,
                SectionTitle('Visits', trailing: Text('${visits.length} recorded', style: TextStyle(color: context.brand.muted))),
                if (visits.isEmpty)
                  const FormHint('No visits yet.')
                else
                  SectionCard(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in visits.take(30))
                          Chip(
                            avatar: const Icon(Icons.login_rounded, size: 16),
                            label: Text('${formatShortDate(BhutanTime.toBhutan(v.checkedInAt))} ${formatTime(v.checkedInAt)}'),
                          ),
                      ],
                    ),
                  ),
              ],
              second: [const SectionTitle('Member card'), card],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renew(BuildContext context) async {
    final subs = membershipsOf(ref.read(gymSubscriptionsProvider(_venueId)).valueOrNull ?? const [], m.id);
    final start = renewalStart(subs, BhutanTime.today());
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _RenewDialog(member: m, venueId: _venueId, start: start),
    );
    if (done == true) refreshGym(ref, _venueId);
  }
}

class _RenewDialog extends ConsumerStatefulWidget {
  final GymMember member;
  final String venueId;
  final DateTime start;

  const _RenewDialog({required this.member, required this.venueId, required this.start});

  @override
  ConsumerState<_RenewDialog> createState() => _RenewDialogState();
}

class _RenewDialogState extends ConsumerState<_RenewDialog> {
  final _form = GlobalKey<FormState>();
  PackageSale? _sale;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    return AlertDialog(
      title: Text('Package for ${widget.member.fullName}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoRow(
                  icon: Icons.event_available_rounded,
                  text: widget.start == today
                      ? 'Starts today'
                      : 'Starts ${formatDate(widget.start)}, the day their current package expires',
                ),
                const SizedBox(height: 12),
                PackageFields(venueId: widget.venueId, start: widget.start, onChanged: (s) => _sale = s),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  if (!_form.currentState!.validate() || _sale == null) return;
                  setState(() => _saving = true);
                  final ok = await runAction(
                    context,
                    () => ref.read(gymRepositoryProvider).renewMember(widget.member.id, _sale!),
                    success: 'Package added',
                  );
                  if (!context.mounted) return;
                  setState(() => _saving = false);
                  if (ok) Navigator.pop(context, true);
                },
          child: const Text('Save package'),
        ),
      ],
    );
  }
}
