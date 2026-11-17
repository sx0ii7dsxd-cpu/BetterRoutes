import 'dart:math';

import 'package:better_routes/services/warehouse_code_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generates exactly five numeric digits after WH-', () {
    final code = generateWarehouseCode(Random(7));

    expect(RegExp(warehouseCodePattern).hasMatch(code), isTrue);
  });

  test('generated code is within the five-digit range', () {
    final code = generateWarehouseCode(Random(11));
    final number = int.parse(code.substring(3));

    expect(number, inInclusiveRange(10000, 99999));
  });
}
