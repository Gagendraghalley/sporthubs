import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/member_qr.dart';
import '../widgets/gym_widgets.dart';

/// The front desk: scan a member's QR code (or type their code). It works
/// only when they have a membership at this gym covering today.
class CheckInScreen extends ConsumerWidget {
  final String venueId;

  const CheckInScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Check in',
      builder: (context, access) => AppPage(title: 'Check in · ${access.venue.name}', body: _CheckInBody(venueId: venueId)),
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
  bool _busy = false;
  CheckInResult? _result;
  String? _error;

  /// The last thing scanned and when, so one card held up isn't checked in
  /// over and over.
  String? _lastRaw;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _scanner.dispose();
    _code.dispose();
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

  Future<void> _checkIn(String raw) async {
    final member = MemberQr.parse(raw);
    if (member == null) {
      setState(() {
        _result = null;
        _error = "That isn't a SportsHub member code.";
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(gymRepositoryProvider).checkIn(widget.venueId, member);
      if (!mounted) return;
      setState(() => _result = result);
      _code.clear();
      ref.invalidate(gymCheckInsTodayProvider(widget.venueId));
      ref.invalidate(gymDashboardProvider(widget.venueId));
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = null;
          _error = friendlyError(e);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(gymCheckInsTodayProvider(widget.venueId));
    return ListView(
      padding: pagePadding(context),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _scanner,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => ColoredBox(
                    color: Colors.black87,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error.errorCode == MobileScannerErrorCode.permissionDenied
                              ? 'Allow the camera to scan, or type the member code below.'
                              : 'No camera here. Type the member code below.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
                if (_busy) const ColoredBox(color: Colors.black38, child: Center(child: CircularProgressIndicator())),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Or type the member code', hintText: '4K7P9Q'),
                onSubmitted: (v) => _checkIn(v),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(onPressed: _busy ? null : () => _checkIn(_code.text), child: const Text('Check in')),
          ],
        ),
        const SizedBox(height: 14),
        if (_result != null) _ResultCard(result: _result!),
        if (_error != null) _ErrorCard(message: _error!),
        SectionTitle(
          'Today',
          trailing: Text('${today.valueOrNull?.length ?? 0} check-ins', style: TextStyle(color: context.brand.muted)),
        ),
        AsyncValueView<List<GymCheckIn>>(
          value: today,
          onRetry: () => ref.invalidate(gymCheckInsTodayProvider(widget.venueId)),
          data: (list) => list.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('Nobody has checked in yet today.'))
              : Card(
                  child: Column(
                    children: [
                      for (final c in list)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.login_rounded),
                          title: Text(c.memberName ?? 'Member'),
                          trailing: Text(formatTime(c.checkedInAt)),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final CheckInResult result;

  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = result.daysLeft <= 3 ? brand.warning : brand.success;
    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: color, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome, ${result.memberName}', style: context.text.titleMedium),
                  Text('${result.planName} · until ${formatDate(result.endDate)}'),
                  Text(
                    result.daysLeft == 1 ? 'Last day of their membership' : '${result.daysLeft} days left',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  if (result.earlierToday > 0)
                    Text('Already checked in earlier today', style: TextStyle(color: brand.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final danger = context.brand.danger;
    return Card(
      color: danger.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.cancel_rounded, color: danger, size: 44),
            const SizedBox(width: 14),
            Expanded(child: Text(message, style: context.text.titleSmall)),
          ],
        ),
      ),
    );
  }
}
