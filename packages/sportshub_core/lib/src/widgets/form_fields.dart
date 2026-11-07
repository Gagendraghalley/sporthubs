import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/brand.dart';
import '../utils/dzongkhags.dart';

/// Choose a dzongkhag.
class DzongkhagField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool required;
  final String label;

  const DzongkhagField({super.key, required this.value, required this.onChanged, this.required = true, this.label = 'Dzongkhag'});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: required ? '$label *' : label),
      items: [for (final d in dzongkhags) DropdownMenuItem(value: d, child: Text(d))],
      onChanged: onChanged,
      validator: required ? (v) => v == null ? 'Choose the dzongkhag' : null : null,
    );
  }
}

/// Five stars, filled to [rating].
class RatingStars extends StatelessWidget {
  final double rating;
  final double size;

  const RatingStars({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : rating >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: const Color(0xFFF5A623),
          ),
      ],
    );
  }
}

/// Tap a star to rate 1 to 5.
class RatingPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const RatingPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            tooltip: '$i star${i == 1 ? '' : 's'}',
            iconSize: 40,
            onPressed: () => onChanged(i),
            icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFF5A623)),
          ),
      ],
    );
  }
}

/// A photo from the gallery (or camera), made small enough to upload
/// quickly; null when they cancel.
Future<({Uint8List bytes, String contentType})?> pickPhoto(BuildContext context, {bool camera = false}) async {
  final file = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 80,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return (bytes: bytes, contentType: imageContentType(bytes));
}

/// What kind of image [bytes] are, from their first bytes.
@visibleForTesting
String imageContentType(Uint8List bytes) {
  if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'image/png';
  if (bytes.length > 12 && String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') return 'image/webp';
  return 'image/jpeg';
}

/// A required field's label: 'Name *'.
String requiredLabel(String label) => '$label *';

/// Muted helper text under a form section.
class FormHint extends StatelessWidget {
  final String text;

  const FormHint(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: context.text.bodySmall?.copyWith(color: context.brand.muted));
}
