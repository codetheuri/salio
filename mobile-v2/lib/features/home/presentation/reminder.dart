import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../core/time/shop_time.dart';

/// Hands a link to another app: the dialer, SMS, WhatsApp. Replaced in
/// tests, which have none. False when no app took it.
typedef LaunchExternal = Future<bool> Function(Uri uri);

final launchExternalProvider = Provider<LaunchExternal>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// The dialer, with the number filled in; the call is the user's to start.
Uri callLink(String phone) => Uri(scheme: 'tel', path: phone);

/// A polite reminder, in the app's language: who it is from, what is owed,
/// and since when. Sent from the shop's own WhatsApp or SMS, so it costs
/// the shop nothing and comes from a number the customer knows.
String reminderText(
  AppLocalizations l10n, {
  required String customer,
  required String shop,
  required int owedCents,
  DateTime? overdueSince,
  required String locale,
}) {
  final amount = Money.format(owedCents, compact: true);
  return overdueSince == null
      ? l10n.reminderText(customer, shop, amount)
      : l10n.reminderTextOverdue(
          customer,
          shop,
          amount,
          ShopTime.date(overdueSince, locale),
        );
}

/// WhatsApp's link for [phone] (E.164) with [text] ready to send.
Uri whatsAppLink(String phone, String text) => Uri.https(
  'wa.me',
  '/${phone.replaceAll(RegExp(r'\D'), '')}',
  {'text': text},
);

/// An SMS to [phone] with [text] ready to send.
Uri smsLink(String phone, String text) =>
    Uri(scheme: 'sms', path: phone, queryParameters: {'body': text});

/// Asks WhatsApp or SMS, then opens it with the reminder written. Says so
/// when neither app could take it.
Future<void> sendReminder(
  BuildContext context,
  WidgetRef ref, {
  required String phone,
  required String text,
}) async {
  final l10n = AppLocalizations.of(context);
  final via = await showModalBottomSheet<Uri>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: Text(l10n.remindWhatsApp),
            onTap: () => Navigator.pop(context, whatsAppLink(phone, text)),
          ),
          ListTile(
            leading: const Icon(Icons.sms_outlined),
            title: Text(l10n.remindSms),
            onTap: () => Navigator.pop(context, smsLink(phone, text)),
          ),
        ],
      ),
    ),
  );
  if (via == null) return;
  final opened = await ref.read(launchExternalProvider)(via);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.remindNoApp)));
  }
}
