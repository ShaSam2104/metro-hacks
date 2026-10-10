import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../repositories/ticket_repository.dart';
import 'ticket_pdf_downloader.dart';

class TicketPdfService {
  const TicketPdfService();

  Future<void> download(TicketOrder order) async {
    final bytes = await build(order);
    await downloadTicketPdf(
      bytes,
      'metrolink-pass-${order.id.substring(0, 8)}.pdf',
    );
  }

  Future<Uint8List> build(TicketOrder order) async {
    final document = pw.Document();
    final verificationPayload =
        'metrolink-demo://ticket/${order.id}?status=${order.status}&fare=${order.fareAmount}';
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(28),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MetroLink journey pass',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text('One City, One Journey'),
              pw.Divider(height: 28),
              pw.Text('Rider', style: const pw.TextStyle(fontSize: 10)),
              pw.Text(order.riderName, style: const pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 14),
              pw.Text('Journey', style: const pw.TextStyle(fontSize: 10)),
              pw.Text('${order.originName} to ${order.destinationName}'),
              pw.SizedBox(height: 14),
              pw.Text(
                'Prototype fare',
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Text(
                'Rs ${order.fareAmount}',
                style: const pw.TextStyle(fontSize: 16),
              ),
              pw.Spacer(),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: verificationPayload,
                  width: 130,
                  height: 130,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text('Pass ID: ${order.id}')),
              pw.SizedBox(height: 6),
              pw.Text(
                'Demo pass only. This QR encodes the MetroLink order reference; it is not valid for operator gate entry.',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
    return document.save();
  }
}
