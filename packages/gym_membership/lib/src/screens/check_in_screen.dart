import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/member_qr.dart';
import '../data/registered_member.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';
import '../widgets/member_photo.dart';

/// The front desk: scan a member's QR card (or type their member code). It
/// works only when their package at this gym covers today; otherwise it says
/// why, and opens their page to renew.
class CheckInScreen extends ConsumerWidget {
  final String venueId;

  const CheckInScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Check-in',
      permission: GymPermission.checkIn,
      builder: (context, access) => AppPage(title: 'Check-in', body: _CheckInBody(venueId: venueId)),
    );
  }
}

class _CheckInBody extends ConsumerStatefulWidget {
  final String venueId;

  const _CheckInBody({required this.venueId});

  @override
  ConsumerState<_CheckInBody> createState() => _CheckInBodyState();
}

class _CheckInBodyState extends ConsumerState<_CheckInBody> {
  final _scanner = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: [BarcodeFormat.qrCode]);
  final _code = TextEditingController();

  /// A USB QR scanner at the counter types the card into the box and
  /// presses Enter, so on a computer the box keeps the cursor.
  final _codeFocus = FocusNode();
  bool _busy = false;
  CheckInResult? _result;
  DateTime? _resultAt;
  String? _error;

  bool get _atCounter => MediaQuery.sizeOf(context).width >= 900;

  bool _looksLikePhone(String value) {
    final digits = value.trim().replaceAll(RegExp(r'[\s()+-]'), '');
    return RegExp(r'^[0-9]{8,15}$').hasMatch(digits);
  }

  /// What the viewfinder shows: ready, checking, or the last outcome for a
  /// moment (a green or red flash), then ready again.
  _ScanState _scan = _ScanState.ready;
  Timer? _settle;

  void _show(_ScanState state) {
    _settle?.cancel();
    setState(() => _scan = state);
    if (state == _ScanState.ok || state == _ScanState.refused) {
      _settle = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _scan = _ScanState.ready);
      });
    }
  }

  /// Whose card was refused, when it's one of this gym's registered members.
  GymMember? _refused;

  /// The last thing scanned and when, so one card held up isn't checked in
  /// over and over.
  String? _lastRaw;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _settle?.cancel();
    _scanner.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null || _busy) return;
    final now = DateTime.now();
    if (raw == _lastRaw && now.difference(_lastAt) < const Duration(seconds: 5)) return;
    _lastRaw = raw;
    _lastAt = now;
    _checkIn(raw);
  }

  Future<void> _checkIn(String raw, {bool allowPhone = false}) async {
    final member = MemberQr.parse(raw);
    if (member == null && !(allowPhone && _looksLikePhone(raw))) {
      setState(() {
        _result = null;
        _refused = null;
        _error = "That isn't a member card or member code.";
      });
      _show(_ScanState.refused);
      _code.clear();
      if (_atCounter) _codeFocus.requestFocus();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _refused = null;
    });
    _show(_ScanState.checking);
    final repo = ref.read(gymRepositoryProvider);
    try {
      final result = member == null
          ? await repo.checkInByPhone(widget.venueId, raw)
          : await repo.checkIn(widget.venueId, member);
      if (!mounted) return;
      setState(() {
        _result = result;
        _resultAt = DateTime.now();
      });
      _show(_ScanState.ok);
      _code.clear();
      ref.invalidate(gymCheckInsTodayProvider(widget.venueId));
      ref.invalidate(gymDashboardProvider(widget.venueId));
    } catch (e) {
      GymMember? refused;
      if (member?.cardToken != null) {
        try {
          refused = await repo.registeredMemberByCard(widget.venueId, member!.cardToken!);
        } catch (_) {}
      } else if (member?.code != null) {
        refused = (ref.read(gymMembersProvider(widget.venueId)).valueOrNull ?? const <GymMember>[])
            .where((m) => m.code == member!.code)
            .firstOrNull;
      }
      if (mounted) {
        setState(() {
          _result = null;
          _error = friendlyError(e);
          _refused = refused;
        });
        _show(_ScanState.refused);
        _code.clear();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_atCounter) _codeFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(gymCheckInsTodayProvider(widget.venueId));
    final list = today.valueOrNull ?? const <GymCheckIn>[];
    final scanner = _Viewfinder(
      controller: _scanner,
      onDetect: _onDetect,
      state: _scan,
    );
    final typeIt = SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.keyboard_alt_outlined, color: context.brand.muted, size: 20),
              const SizedBox(width: 8),
              Text('No card? Enter their member code or phone', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  focusNode: _codeFocus,
                  autofocus: _atCounter,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 4),
                  decoration: InputDecoration(
                    hintText: 'Code or phone number',
                    hintStyle: TextStyle(letterSpacing: 4, color: context.brand.muted.withValues(alpha: 0.5)),
                    helperText: _atCounter ? 'A USB QR scanner works here too: keep the cursor in this box.' : null,
                  ),
                  onSubmitted: (v) => _checkIn(v, allowPhone: true),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _busy ? null : () => _checkIn(_code.text, allowPhone: true),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Check in'),
              ),
            ],
          ),
        ],
      ),
    );
    final outcome = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(a), child: child),
      ),
      child: _result != null
          ? _ResultCard(key: ValueKey(_resultAt), result: _result!, at: _resultAt ?? DateTime.now())
          : _error != null
              ? _ErrorCard(
                  key: ValueKey('e$_error${_refused?.id}'),
                  message: _error!,
                  member: _refused,
                  onOpen: _refused == null ? null : () => context.go(GymRoutes.memberFor(widget.venueId, _refused!.id)),
                )
              : const _Waiting(key: ValueKey('waiting')),
    );
    final visitors = list.map((c) => c.memberId).toSet().length;
    final todayList = AsyncValueView<List<GymCheckIn>>(
      value: today,
      loading: const LoadingSkeleton.rows(),
      onRetry: () => ref.invalidate(gymCheckInsTodayProvider(widget.venueId)),
      data: (list) => list.isEmpty
          ? SectionCard(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Nobody has checked in yet today.', style: TextStyle(color: context.brand.muted)),
              ),
            )
          : SectionCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final c in list.take(40))
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: BrandColors.green.withValues(alpha: 0.12),
                        child: Text(
                          (c.memberName ?? 'M').trim().isEmpty ? 'M' : (c.memberName ?? 'M').trim()[0].toUpperCase(),
                          style: const TextStyle(color: BrandColors.green, fontWeight: FontWeight.w800),
                        ),
                      ),
                      title: Text(c.memberName ?? 'Member', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(timeAgo(c.checkedInAt)),
                      trailing: Text(formatTime(c.checkedInAt), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: c.gymMemberId == null
                          ? null
                          : () => context.go(GymRoutes.memberFor(widget.venueId, c.gymMemberId!)),
                    ),
                ],
              ),
            ),
    );

    return ListView(
      padding: pagePadding(context),
      children: [
        ResponsiveColumns(
          breakpoint: 980,
          flex: (6, 5),
          first: [scanner, const SizedBox(height: 14), typeIt],
          second: [
            if (MediaQuery.sizeOf(context).width < 980) const SizedBox(height: 14),
            outcome,
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _Stat(label: 'Check-ins today', value: list.length, color: BrandColors.green)),
                const SizedBox(width: 12),
                Expanded(child: _Stat(label: 'Members today', value: visitors, color: BrandColors.blue)),
              ],
            ),
            const SectionTitle('Today'),
            todayList,
          ],
        ),
      ],
    );
  }
}

/// A number for today, counting up.
class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _Stat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => ServiceStat(label: label, value: value, color: color);
}

/// Before anyone is scanned: what to do.
class _Waiting extends StatelessWidget {
  const _Waiting({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: BrandColors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.qr_code_2_rounded, color: BrandColors.orange, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Scan the QR card from their phone or printed card, or enter their member code or phone number. '
              'Only a package that covers today checks them in.',
              style: TextStyle(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the viewfinder is showing.
enum _ScanState { ready, checking, ok, refused }

/// The camera, with a window to hold the card in: the rest dimmed, corner
/// brackets, a line sweeping down while it's ready, a pill saying what's
/// happening, and a green or red flash for the outcome.
class _Viewfinder extends StatefulWidget {
  final MobileScannerController controller;
  final void Function(BarcodeCapture) onDetect;
  final _ScanState state;

  const _Viewfinder({required this.controller, required this.onDetect, required this.state});

  @override
  State<_Viewfinder> createState() => _ViewfinderState();
}

class _ViewfinderState extends State<_Viewfinder> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(_Viewfinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _run();
  }

  /// The line sweeps only while it's ready (and the device allows motion).
  void _run() {
    if (widget.state == _ScanState.ready && !reduceMotion(context)) {
      if (!_sweep.isAnimating) _sweep.repeat(reverse: true);
    } else {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final brand = context.brand;
    final color = switch (state) {
      _ScanState.ok => brand.success,
      _ScanState.refused => brand.danger,
      _ScanState.checking => BrandColors.blue,
      _ScanState.ready => BrandColors.orange,
    };
    final (IconData icon, String label) = switch (state) {
      _ScanState.ready => (Icons.qr_code_scanner_rounded, 'Ready to scan'),
      _ScanState.checking => (Icons.hourglass_top_rounded, 'Checking…'),
      _ScanState.ok => (Icons.check_circle_rounded, 'Checked in'),
      _ScanState.refused => (Icons.cancel_rounded, 'Not checked in'),
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: LayoutBuilder(
          builder: (context, c) {
            final side = c.biggest.shortestSide * 0.62;
            final window = Rect.fromCenter(center: c.biggest.center(Offset.zero), width: side, height: side);
            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: widget.controller,
                  onDetect: widget.onDetect,
                  errorBuilder: (context, error) => ColoredBox(
                    color: BrandColors.night,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.no_photography_outlined, color: Colors.white.withValues(alpha: 0.7), size: 40),
                            const SizedBox(height: 12),
                            Text(
                              error.errorCode == MobileScannerErrorCode.permissionDenied
                                  ? 'Allow camera access to scan, or enter the member code or phone number.'
                                  : 'No camera here. Enter the member code or phone number, or use a USB scanner.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) => CustomPaint(
                      painter: _WindowPainter(window: window, color: color, sweep: state == _ScanState.ready ? _sweep.value : null),
                    ),
                  ),
                ),
                // The outcome's flash over the whole picture.
                IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    color: state == _ScanState.ok || state == _ScanState.refused ? color.withValues(alpha: 0.22) : Colors.transparent,
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: state == _ScanState.ready ? Colors.black.withValues(alpha: 0.55) : color,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Row(
                          key: ValueKey(state),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (state == _ScanState.checking)
                              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            else
                              Icon(icon, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dims all but the [window], draws its corner brackets in [color], and the
/// scanning line at [sweep] (0 top, 1 bottom) when there is one.
class _WindowPainter extends CustomPainter {
  final Rect window;
  final Color color;
  final double? sweep;

  _WindowPainter({required this.window, required this.color, this.sweep});

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(window, const Radius.circular(22));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    final arm = window.width * 0.16;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const r = 22.0;
    for (final (corner, dx, dy) in [
      (window.topLeft, 1.0, 1.0),
      (window.topRight, -1.0, 1.0),
      (window.bottomLeft, 1.0, -1.0),
      (window.bottomRight, -1.0, -1.0),
    ]) {
      final path = Path()
        ..moveTo(corner.dx, corner.dy + dy * (r + arm))
        ..lineTo(corner.dx, corner.dy + dy * r)
        ..arcToPoint(Offset(corner.dx + dx * r, corner.dy), radius: const Radius.circular(r), clockwise: dx * dy > 0)
        ..lineTo(corner.dx + dx * (r + arm), corner.dy);
      canvas.drawPath(path, pen);
    }
    if (sweep != null) {
      final y = window.top + 14 + (window.height - 28) * sweep!;
      final line = Rect.fromLTRB(window.left + 16, y - 1.5, window.right - 16, y + 1.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(line, const Radius.circular(2)),
        Paint()
          ..shader = LinearGradient(colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)]).createShader(line),
      );
      // A soft glow trailing the line.
      final glow = Rect.fromLTRB(window.left + 16, y - 26, window.right - 16, y);
      canvas.drawRect(
        glow,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
          ).createShader(glow),
      );
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window || old.color != color || old.sweep != sweep;
}

/// 'CHECKED IN · 2:14 PM' or 'NOT CHECKED IN': the outcome, before anything
/// else.
class _Outcome extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const _Outcome({required this.text, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text, style: TextStyle(color: context.brand.readable(color), fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final CheckInResult result;

  /// When it was recorded.
  final DateTime at;

  const _ResultCard({super.key, required this.result, required this.at});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = result.daysLeft <= 3 ? brand.warning : brand.success;
    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Outcome(text: 'CHECKED IN · ${formatTime(at)}', icon: Icons.check_circle_rounded, color: brand.success),
            Row(
              children: [
                if (result.gymMemberId != null)
                  MemberPhoto(path: result.photoPath, name: result.memberName, size: 88)
                else
                  Icon(Icons.check_circle_rounded, color: color, size: 44),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.memberName, style: context.text.titleLarge),
                      if (result.memberCode != null) Text('Member code ${result.memberCode}', style: TextStyle(color: brand.muted)),
                      Text('${result.planName} · until ${formatDate(result.endDate)}'),
                      Text(
                        result.daysLeft == 1 ? 'Last day of their package' : '${result.daysLeft} days left',
                        style: TextStyle(color: brand.readable(color), fontWeight: FontWeight.w700),
                      ),
                      if (result.earlierToday > 0) Text('Already checked in earlier today', style: TextStyle(color: brand.muted)),
                    ],
                  ),
                ),
              ],
            ),
            if (result.medicalNotes != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: brand.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.medical_information_outlined, color: brand.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(result.medicalNotes!)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  /// The registered member it was about, to open their page (to renew).
  final GymMember? member;
  final VoidCallback? onOpen;

  const _ErrorCard({super.key, required this.message, this.member, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final danger = context.brand.danger;
    return Card(
      color: danger.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Outcome(text: 'NOT CHECKED IN', icon: Icons.cancel_rounded, color: danger),
            Row(
              children: [
                if (member != null)
                  MemberPhoto(path: member!.photoPath, name: member!.fullName, size: 64)
                else
                  Icon(Icons.block_rounded, color: danger, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(message, style: context.text.titleSmall),
                      if (onOpen != null) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: onOpen,
                          icon: const Icon(Icons.autorenew_rounded),
                          label: const Text('Open their page to renew'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
