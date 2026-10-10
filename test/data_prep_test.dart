import 'package:flutter_test/flutter_test.dart';
import 'package:metro_hacks/src/data_prep.dart';

void main() {
  test(
    'transfer estimate includes station access and rounded walking time',
    () {
      expect(estimateTransferMinutes(0), 4);
      expect(estimateTransferMinutes(60), 5);
      expect(estimateTransferMinutes(61), 6);
    },
  );
}
