import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:clipboard/clipboard.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_repository.dart';
import '../data/member_qr.dart';
import '../data/registered_member.dart';

/// A registered member's card and what the desk does with it: download it
/// (in a browser) or share it (on a phone, WhatsApp is in the share sheet),
/// open their WhatsApp chat with a message ready, or give them a new card.
class MemberCardPanel extends ConsumerStatefulWidget {
  final String gymName;
  final GymMember member;

  /// The last day their packages cover, if any.
  final DateTime? until;

  /// What the card says without [until]: 'No package yet', 'Gym · ended 3 Oct'.
  final String noPackage;

  /// Whether they may make a new card ('gym.register').
  final bool canReissue;

  const MemberCardPanel({
    super.key,
    required this.gymName,
    required this.member,
    required this.until,
    required this.noPackage,
    this.canReissue = false,
  });

  @override
  ConsumerState<MemberCardPanel> createState() => _MemberCardPanelState();
}

class _MemberCardPanelState extends ConsumerState<MemberCardPanel> {
  final _cardKey = GlobalKey();
  final _qrKey = GlobalKey();
  bool _busy = false;

  GymMember get m => widget.member;
  String? get _until => widget.until == null ? null : formatDate(widget.until!);
  String get _message => cardMessage(member: m, gymName: widget.gymName, validUntil: _until);

  @override
  Widget build(BuildContext context) {
    final photo = m.photoPath == null ? null : ref.watch(gymMemberPhotoProvider(m.photoPath!));
    // The picture is taken as it's drawn: wait for their photo.
    final ready = !_busy && (photo == null || !photo.isLoading);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: RegisteredMemberCard(
              gymName: widget.gymName,
              member: m,
              photo: photo?.valueOrNull,
              package: _until == null ? widget.noPackage : 'Valid until $_until',
              repaintKey: _cardKey,
              qrRepaintKey: _qrKey,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: ready ? _copyQrCode : null,
              icon: const Icon(Icons.content_copy_rounded),
              label: const Text('Copy QR code'),
            ),
            OutlinedButton.icon(
              onPressed: () => openWhatsApp(context, m.phone, message: _message),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp message'),
            ),
            if (widget.canReissue)
              TextButton.icon(
                onPressed: _busy ? null : _reissue,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('New card'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const FormHint(
          'Copy the QR image, then paste it into the WhatsApp chat with the welcome message.',
        ),
      ],
    );
  }

  Future<void> _copyQrCode() async {
    setState(() => _busy = true);
    try {
      final png = await cardPicture(_qrKey);
      await FlutterClipboard.copyImage(png);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR code copied. Paste it into WhatsApp.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not copy the QR image: ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reissue() async {
    final sure = await confirmAction(
      context,
      title: 'Give ${m.fullName} a new card?',
      message: 'Their old QR card stops working (for a lost or shared card). Their member code stays the same.',
      confirmLabel: 'New card',
    );
    if (!sure || !mounted) return;
    final ok = await runAction(context, () => ref.read(gymRepositoryProvider).reissueCard(m.id),
        success: 'New card made. Send it to them.');
    if (ok) ref.invalidate(gymMemberProvider(m.id));
  }
}

/// A registered member's card: the gym, their photo and name, the QR code
/// the desk scans, their member code and how long their package runs.
/// Drawn in fixed colours, the same in both themes, so the picture sent on
/// WhatsApp always looks like this. Wrap it in a [RepaintBoundary] with
/// [repaintKey] to take its picture ([cardPicture]).
class RegisteredMemberCard extends StatelessWidget {
  final String gymName;
  final GymMember member;

  /// Their photo, already loaded (the picture can't wait for it).
  final Uint8List? photo;

  /// 'Valid until 8 Feb 2027', or what they should do to get one.
  final String package;
  final GlobalKey? repaintKey;
  final GlobalKey? qrRepaintKey;

  const RegisteredMemberCard({
    super.key,
    required this.gymName,
    required this.member,
    required this.package,
    this.photo,
    this.repaintKey,
    this.qrRepaintKey,
  });

  static const width = 340.0;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final card = Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [BrandColors.navy, BrandColors.midnight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: white, fontFamily: brandFont),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center_rounded, color: BrandColors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(gymName,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Text('MEMBER', style: TextStyle(color: white.withValues(alpha: 0.6), fontSize: 11, letterSpacing: 2)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _Photo(photo: photo, name: member.fullName),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.fullName,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                      const SizedBox(height: 4),
                      Text(package, style: TextStyle(color: white.withValues(alpha: 0.8), fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            RepaintBoundary(
              key: qrRepaintKey,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: white, borderRadius: BorderRadius.circular(18)),
                child: QrImageView(
                  data: MemberQr.encodeCard(member.qrToken),
                  size: 190,
                  backgroundColor: white,
                  padding: EdgeInsets.zero,
                  semanticsLabel: "${member.fullName}'s member QR code",
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(member.code, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6)),
            const SizedBox(height: 4),
            Text(
              'Show this at the counter when you come in.',
              textAlign: TextAlign.center,
              style: TextStyle(color: white.withValues(alpha: 0.8), fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Container(height: 3, width: 44, decoration: BoxDecoration(color: BrandColors.orange, borderRadius: BorderRadius.circular(2))),
          ],
        ),
      ),
    );
    return repaintKey == null ? card : RepaintBoundary(key: repaintKey, child: card);
  }
}

class _Photo extends StatelessWidget {
  final Uint8List? photo;
  final String name;

  const _Photo({required this.photo, required this.name});

  @override
  Widget build(BuildContext context) {
    const size = 72.0;
    if (photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.memory(photo!, width: size, height: size, fit: BoxFit.cover),
      );
    }
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 24)),
    );
  }
}

/// The card's picture, as a PNG three times its size on screen.
Future<Uint8List> cardPicture(GlobalKey repaintKey) async {
  final boundary = repaintKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// 'Karma-Wangmo-4K7P9Q.png'.
String cardFileName(GymMember member) =>
    '${member.fullName.trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-${member.code}.png';

/// What the WhatsApp chat starts with: who, where, their code and package.
String cardMessage({required GymMember member, required String gymName, String? validUntil}) =>
    'Kuzuzangpo ${firstName(member.fullName, fallback: 'la')}! Welcome to $gymName. '
    'Your member code is ${member.code}${validUntil == null ? '' : ' and your package is valid until $validUntil'}. '
    'Show the QR card we are sending you at the counter each time you come in.';

/// Saves the card's picture as a file: a download in a browser.
Future<void> downloadCard(Uint8List png, GymMember member) {
  final name = cardFileName(member);
  return XFile.fromData(png, mimeType: 'image/png', name: name).saveTo(name);
}

/// Shares the card's picture: the phone's share sheet (WhatsApp is in it),
/// or a download on a computer whose browser can't share files.
Future<void> shareCard(BuildContext context, Uint8List png, {required GymMember member, required String message}) async {
  final box = context.findRenderObject() as RenderBox?;
  final name = cardFileName(member);
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(png, mimeType: 'image/png', name: name)],
    fileNameOverrides: [name],
    text: message,
    subject: 'Your member card',
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}
