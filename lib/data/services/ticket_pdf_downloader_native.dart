import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<void> downloadTicketPdf(Uint8List bytes, String filename) async {
  final didOpenShareSheet = await Printing.sharePdf(
    bytes: bytes,
    filename: filename,
  );
  if (!didOpenShareSheet) {
    throw StateError('Could not open the PDF share sheet.');
  }
}
