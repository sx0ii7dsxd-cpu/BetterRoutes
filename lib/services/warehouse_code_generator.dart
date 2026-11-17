import 'dart:math';

const String warehouseCodePattern = r'^WH-[0-9]{5}$';

String generateWarehouseCode([Random? random]) {
  final source = random ?? Random.secure();
  final number = 10000 + source.nextInt(90000);
  return 'WH-$number';
}
