import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the browser (or the app that handles it); tells the person
/// when nothing could open it.
Future<void> openExternal(BuildContext context, Uri url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(url, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  } catch (_) {}
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not open ${url.host.isEmpty ? url : url.host}')));
  }
}

/// Calls [phone] ('+97517123456').
Future<void> callPhone(BuildContext context, String phone) => openExternal(context, Uri(scheme: 'tel', path: phone));

/// WhatsApp chat with [phone], with [message] typed in, ready to send.
Future<void> openWhatsApp(BuildContext context, String phone, {String? message}) =>
    openExternal(context, whatsAppLink(phone, message: message));

/// `wa.me/<the number's digits>`, with `?text=` when there's a [message].
Uri whatsAppLink(String phone, {String? message}) => Uri.https(
      'wa.me',
      '/${phone.replaceAll(RegExp(r'[^0-9]'), '')}',
      message == null ? null : {'text': message},
    );

/// Google Maps directions to a place.
Future<void> openDirections(BuildContext context, double latitude, double longitude) => openExternal(
      context,
      Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': '$latitude,$longitude'}),
    );
