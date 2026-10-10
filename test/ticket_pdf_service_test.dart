import 'package:flutter_test/flutter_test.dart';

import 'package:metro_hacks/data/repositories/ticket_repository.dart';
import 'package:metro_hacks/data/services/ticket_pdf_service.dart';

void main() {
  test('builds a PDF journey pass with a QR payload', () async {
    final bytes = await const TicketPdfService().build(
      TicketOrder(
        id: '8b9c3b11-cc57-4a91-b076-086c527c613c',
        riderName: 'Samya Shah',
        travelForSelf: true,
        originName: 'Thaltej Gam Metro',
        destinationName: 'Gujarat University',
        fareAmount: 25,
        status: 'issued',
        createdAt: DateTime.utc(2026, 10, 11),
      ),
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
