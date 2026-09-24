import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'android_system_volume_controller.dart';
import 'linux_system_volume_controller.dart';
import 'system_volume_controller.dart';

final systemVolumeControllerProvider = Provider<SystemVolumeController>((ref) {
  final controller = Platform.isLinux
      ? LinuxSystemVolumeController()
      : AndroidSystemVolumeController();
  ref.onDispose(controller.dispose);
  return controller;
});
