import 'package:flutter_test/flutter_test.dart';

import '../tool/quick_pop_production_smoke.dart' as smoke;

void main() {
  test(
    'deployed Firebase accepts one four-human Quick Pop v2 group',
    smoke.mainFour,
    timeout: const Timeout(Duration(seconds: 55)),
  );
}
