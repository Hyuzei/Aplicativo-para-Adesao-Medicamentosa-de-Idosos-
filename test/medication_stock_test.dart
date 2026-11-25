import 'package:flutter_test/flutter_test.dart';

import 'package:med_app/models/medication.dart';

void main() {
  group('medication stock', () {
    test('decrements only when a dose first becomes taken', () {
      expect(
        stockAfterDoseStatus(
          stock: 4,
          previousStatus: DoseStatus.pending,
          nextStatus: DoseStatus.taken,
        ),
        3,
      );
      expect(
        stockAfterDoseStatus(
          stock: 3,
          previousStatus: DoseStatus.taken,
          nextStatus: DoseStatus.taken,
        ),
        3,
      );
    });

    test('restores a unit when a taken dose is corrected', () {
      expect(
        stockAfterDoseStatus(
          stock: 3,
          previousStatus: DoseStatus.taken,
          nextStatus: DoseStatus.missed,
        ),
        4,
      );
    });

    test('does not track an unknown stock or decrement below zero', () {
      expect(
        stockAfterDoseStatus(
          stock: null,
          previousStatus: DoseStatus.pending,
          nextStatus: DoseStatus.taken,
        ),
        isNull,
      );
      expect(
        stockAfterDoseStatus(
          stock: 0,
          previousStatus: DoseStatus.pending,
          nextStatus: DoseStatus.taken,
        ),
        0,
      );
    });

    test('detects only a transition into low stock', () {
      expect(crossedLowStockThreshold(4, 3), isTrue);
      expect(crossedLowStockThreshold(null, 3), isTrue);
      expect(crossedLowStockThreshold(3, 2), isFalse);
      expect(crossedLowStockThreshold(4, 4), isFalse);
    });
  });
}
