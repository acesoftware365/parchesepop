import 'package:flutter_test/flutter_test.dart';

import '../tool/quick_pop_production_smoke.dart' as smoke;

void main() {
  test(
    'deployed Firebase accepts one human Quick Pop v2 group',
    smoke.main,
    timeout: const Timeout(Duration(seconds: 55)),
  );
}
