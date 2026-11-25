enum DoseStatus { pending, taken, missed }

const lowStockThreshold = 4;

int? stockAfterDoseStatus({
  required int? stock,
  required DoseStatus previousStatus,
  required DoseStatus nextStatus,
}) {
  if (stock == null) return null;
  if (previousStatus == DoseStatus.taken && nextStatus != DoseStatus.taken) {
    return stock + 1;
  }
  if (previousStatus != DoseStatus.taken &&
      nextStatus == DoseStatus.taken &&
      stock > 0) {
    return stock - 1;
  }
  return stock;
}

bool crossedLowStockThreshold(int? previousStock, int? currentStock) =>
    currentStock != null &&
    currentStock < lowStockThreshold &&
    (previousStock == null || previousStock >= lowStockThreshold);

class Medication {
  Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.times,
    required this.stock,
  });

  final String id;
  String name;
  String dosage;
  String instructions;
  List<String> times;
  int? stock;
}

class DoseRecord {
  const DoseRecord({
    required this.medication,
    required this.time,
    required this.status,
  });

  final Medication medication;
  final String time;
  final DoseStatus status;
}
