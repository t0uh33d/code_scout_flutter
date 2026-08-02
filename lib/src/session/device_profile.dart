import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What the app is running on and which build of it is running.
///
/// Every field is nullable. Collecting this touches platform channels, and an
/// observability library must never be the reason an app fails to start — so
/// anything that does not answer is simply left out, and the dashboard says
/// "Unknown device" rather than the launch going unrecorded.
class DeviceProfile {
  const DeviceProfile({
    this.model,
    this.osName,
    this.osVersion,
    this.appVersion,
    this.buildNumber,
  });

  final String? model;
  final String? osName;
  final String? osVersion;
  final String? appVersion;
  final String? buildNumber;

  static const DeviceProfile empty = DeviceProfile();

  /// Reads the platform. [captureDevice] and [captureApp] are the two config
  /// flags — until now they were stored and never read, and this is what makes
  /// them mean something.
  static Future<DeviceProfile> collect({
    bool captureDevice = true,
    bool captureApp = true,
  }) async {
    String? model;
    String? osName;
    String? osVersion;
    String? appVersion;
    String? buildNumber;

    if (captureDevice) {
      final device = await _device();
      model = device.model;
      osName = device.osName;
      osVersion = device.osVersion;
    }

    if (captureApp) {
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = _orNull(info.version);
        buildNumber = _orNull(info.buildNumber);
      } catch (_) {
        // Left null.
      }
    }

    return DeviceProfile(
      model: model,
      osName: osName,
      osVersion: osVersion,
      appVersion: appVersion,
      buildNumber: buildNumber,
    );
  }

  static Future<DeviceProfile> _device() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        // Build.MODEL is the name on the box: "Pixel 7", "SM-G991B".
        return DeviceProfile(
          model: _orNull(info.model),
          osName: 'Android',
          osVersion: _orNull(info.version.release),
        );
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        // modelName, not model: `model` answers "iPhone" for every iPhone ever
        // made, which would collapse the whole device list into one row.
        return DeviceProfile(
          model: _orNull(info.modelName),
          osName: 'iOS',
          osVersion: _orNull(info.systemVersion),
        );
      }
    } catch (_) {
      // Fall through to the platform's own answer.
    }

    // Desktop, or a phone whose platform channel did not answer. dart:io still
    // knows which OS it is, which is better than nothing on the row.
    return DeviceProfile(
      osName: _platformName(),
      osVersion: _orNull(Platform.operatingSystemVersion),
    );
  }

  static String _platformName() {
    switch (Platform.operatingSystem) {
      case 'macos':
        return 'macOS';
      case 'ios':
        return 'iOS';
      case 'android':
        return 'Android';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      default:
        return Platform.operatingSystem;
    }
  }

  static String? _orNull(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }
}
