import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_repository.dart';

/// A photo the front desk took or chose, before it's uploaded.
typedef PickedPhoto = ({Uint8List bytes, String contentType});

/// A registered member's photo (private, from the gym's folder), or their
/// initials while there's none.
class MemberPhoto extends ConsumerWidget {
  final String? path;
  final String name;
  final double size;

  /// A photo just taken, shown instead of [path].
  final Uint8List? bytes;

  const MemberPhoto({super.key, required this.path, required this.name, this.size = 56, this.bytes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = bytes ?? (path == null ? null : ref.watch(gymMemberPhotoProvider(path!)).valueOrNull);
    final radius = BorderRadius.circular(size * 0.28);
    if (data != null) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.memory(data, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: BrandColors.blue.withValues(alpha: 0.14), borderRadius: radius),
      child: Text(initials, style: TextStyle(color: BrandColors.blue, fontWeight: FontWeight.w800, fontSize: size * 0.34)),
    );
  }
}

/// The registration form's photo: the one taken (or the member's current
/// one), with Take photo (the webcam on a computer, the camera on a phone)
/// and Upload.
class MemberPhotoField extends StatelessWidget {
  final PickedPhoto? picked;
  final String? currentPath;
  final String name;
  final ValueChanged<PickedPhoto?> onChanged;

  const MemberPhotoField({super.key, required this.picked, required this.onChanged, this.currentPath, this.name = ''});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MemberPhoto(path: currentPath, name: name, bytes: picked?.bytes, size: 148),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                final photo = await takeMemberPhoto(context);
                if (photo != null) onChanged(photo);
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(picked == null && currentPath == null ? 'Take photo' : 'Retake'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final photo = await pickPhoto(context);
                if (photo != null) onChanged(photo);
              },
              icon: const Icon(Icons.upload_outlined),
              label: const Text('Upload'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A photo of the member: from the webcam in a browser, with the phone's
/// camera elsewhere. Null when they cancel.
Future<PickedPhoto?> takeMemberPhoto(BuildContext context) async {
  if (!kIsWeb) return pickPhoto(context, camera: true);
  return showDialog<PickedPhoto>(context: context, barrierDismissible: false, builder: (_) => const WebcamDialog());
}

/// The computer's webcam, live: snap, look, retake or use.
class WebcamDialog extends StatefulWidget {
  const WebcamDialog({super.key});

  @override
  State<WebcamDialog> createState() => _WebcamDialogState();
}

class _WebcamDialogState extends State<WebcamDialog> {
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  CameraController? _controller;
  PickedPhoto? _shot;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'No camera found. Upload a photo instead.');
        return;
      }
      final old = _controller;
      final controller = CameraController(_cameras[_index], ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      await old?.dispose();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      final denied = e.code.toLowerCase().contains('permission') || e.code.toLowerCase().contains('denied');
      setState(() => _error = denied
          ? 'The browser blocked the camera. Allow it (the camera icon in the address bar) and try again, or upload a photo.'
          : 'The camera could not start (${e.description ?? e.code}). Upload a photo instead.');
    } catch (e) {
      if (mounted) setState(() => _error = 'The camera could not start. Upload a photo instead.');
    }
  }

  Future<void> _snap() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _shot = (bytes: bytes, contentType: imageContentType(bytes)));
    } catch (_) {
      if (mounted) setState(() => _error = 'The photo could not be taken. Try again, or upload one.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return AlertDialog(
      title: const Text("Member's photo"),
      content: SizedBox(
        width: 480,
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: Colors.black,
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                      ),
                    )
                  : _shot != null
                      ? Image.memory(_shot!.bytes, fit: BoxFit.cover)
                      : ready
                          ? FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: 480,
                                height: 480 / controller.value.aspectRatio,
                                child: CameraPreview(controller),
                              ),
                            )
                          : const Center(child: SportsHubLoader(size: 48, semanticsLabel: 'Starting the camera')),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (_cameras.length > 1 && _shot == null)
          TextButton.icon(
            onPressed: () {
              _index = (_index + 1) % _cameras.length;
              _start();
            },
            icon: const Icon(Icons.cameraswitch_outlined),
            label: const Text('Switch camera'),
          ),
        if (_shot != null) ...[
          OutlinedButton(onPressed: () => setState(() => _shot = null), child: const Text('Retake')),
          FilledButton(onPressed: () => Navigator.pop(context, _shot), child: const Text('Use photo')),
        ] else
          FilledButton.icon(
            onPressed: ready && !_busy ? _snap : null,
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('Snap'),
          ),
      ],
    );
  }
}
