import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// PDFs the server renders (reports, purchase orders): saved on the phone,
/// opened in its PDF viewer, or handed to the share sheet (WhatsApp, email,
/// Drive). Each step is a provider so tests replace it: they have no
/// viewer, share sheet or app folders.

/// Where PDFs are saved: the app's own documents, in `pdf/`. Kept until
/// replaced by a newer copy of the same report, and removed with the app.
final pdfFolderProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/pdf',
    );
    return dir.create(recursive: true);
  },
);

/// Opens a saved PDF in the phone's viewer. False when no app can.
typedef OpenPdf = Future<bool> Function(File file);

final openPdfProvider = Provider<OpenPdf>(
  (ref) =>
      (file) async =>
          (await OpenFilex.open(file.path, type: 'application/pdf')).type ==
          ResultType.done,
);

/// Hands a saved PDF to Android's share sheet.
typedef SharePdf = Future<void> Function(File file, String subject);

final sharePdfProvider = Provider<SharePdf>(
  (ref) => (file, subject) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: subject,
      ),
    );
  },
);

/// Saves [bytes] as [name] in [folder] (the PDF folder's provider),
/// replacing an older copy.
Future<File> savePdf(
  Future<Directory> Function() folder,
  String name,
  List<int> bytes,
) async {
  final dir = await folder();
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  return File('${dir.path}/$safe').writeAsBytes(bytes, flush: true);
}
