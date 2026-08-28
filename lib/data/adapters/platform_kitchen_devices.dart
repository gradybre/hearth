import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'kitchen_devices.dart';

/// The real screen keeper.
class PlatformScreenKeeper implements ScreenKeeper {
  @override
  Future<void> keepAwake() => WakelockPlus.enable();

  @override
  Future<void> release() => WakelockPlus.disable();
}

/// The real timer alerts, on top of the OS notification scheduler.
///
/// Ids are hashed to the 32-bit int the plugin wants, deterministically, so
/// cancelling by the same string cancels the right alert.
class PlatformTimerAlerts implements TimerAlerts {
  PlatformTimerAlerts({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String _channelId = 'hearth_cook_timers';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          // Asked for separately, at the moment the first timer starts —
          // a permission prompt belongs at the stove, not on first launch.
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureReady();
    final IOSFlutterLocalNotificationsPlugin? ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    final MacOSFlutterLocalNotificationsPlugin? macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (macos != null) {
      return await macos.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    await _ensureReady();
    // An alert for a moment that has already passed would fire immediately and
    // say the wrong thing; the ringing list in the session covers that case.
    if (!at.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id: _idOf(id),
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        android: AndroidNotificationDetails(
          _channelId,
          'Cook timers',
          channelDescription: 'Alerts when a cook timer finishes',
          importance: Importance.max,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(String id) async {
    await _ensureReady();
    await _plugin.cancel(id: _idOf(id));
  }

  @override
  Future<void> cancelAll() async {
    await _ensureReady();
    await _plugin.cancelAll();
  }

  /// Stable 31-bit hash: the plugin keys notifications by int, and cancelling
  /// has to find the same one scheduling created.
  static int _idOf(String id) {
    int hash = 0;
    for (final int unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

/// Does nothing, successfully.
///
/// Used in tests and anywhere the platform pieces are not wanted — cook-along
/// still works, it just cannot wake the screen or reach a backgrounded cook.
class NoopScreenKeeper implements ScreenKeeper {
  const NoopScreenKeeper();

  @override
  Future<void> keepAwake() async {}

  @override
  Future<void> release() async {}
}

class NoopTimerAlerts implements TimerAlerts {
  const NoopTimerAlerts();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule({
    required String id,
    required String title,
    required String body,
    required DateTime at,
  }) async {}

  @override
  Future<void> cancel(String id) async {}

  @override
  Future<void> cancelAll() async {}
}
