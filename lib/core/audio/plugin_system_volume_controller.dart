import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'linux_system_volume_controller.dart';
import 'plugin_system_volume_controller.dart';
import 'system_volume_controller.dart';

final systemVolumeControllerProvider = Provider<SystemVolumeController>((ref) {
  final controller = Platform.isLinux
      ? LinuxSystemVolumeController()
      : PluginSystemVolumeController();
  ref.onDispose(controller.dispose);
  return controller;
});
