import 'package:flutter/services.dart';

/// Phone orientations supported by Parchís Pop.
///
/// The game never forces landscape: the operating system can move freely
/// between portrait and either landscape direction as the player rotates the
/// device.
const supportedAppOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

Future<void> enableFlexibleOrientation() =>
    SystemChrome.setPreferredOrientations(supportedAppOrientations);
