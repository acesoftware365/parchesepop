import 'package:flutter/services.dart';

/// Phone orientation supported by Parchese Pop.
///
/// The board and its controls are designed as a single, touch-friendly
/// vertical experience. Keeping portrait avoids the cramped landscape HUD.
const supportedAppOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
];

Future<void> enablePortraitOrientation() =>
    SystemChrome.setPreferredOrientations(supportedAppOrientations);
