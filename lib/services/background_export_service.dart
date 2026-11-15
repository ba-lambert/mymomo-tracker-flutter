import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'export_service.dart';
import 'settings_service.dart';
import 'sms_service.dart';
import 'upload_service.dart';

/// How often the foreground sync service polls for a pending pull request
/// or new SMS. This is the fast path the dashboard's "Request pull" relies
/// on — WorkManager can't go below 15 minutes, but a foreground service
/// (with its own persistent notification, as Android requires for any
/// continuous background work) can poll as often as it likes.
const foregroundSyncInterval = Duration(seconds: 60);

/// Starts the always-on foreground sync service: requests the notification
/// permission it needs to run, configures the poll interval, and starts (or
/// restarts) it. Safe to call on every app launch.
Future<void> startForegroundSync() async {
  final permission = await FlutterForegroundTask.checkNotificationPermission();
  if (permission != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'momo_sync_service',
      channelName: 'MoMo Tracker sync',
      channelDescription: 'Keeps checking for dashboard pull requests and new SMS to upload.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(foregroundSyncInterval.inMilliseconds),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.restartService();
  } else {
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'MoMo Tracker',
      notificationText: 'Syncing messages in the background',
      callback: _foregroundSyncStartCallback,
    );
  }
}

/// Top-level entry point the foreground service isolate calls to install
/// its [TaskHandler]. Must stay top-level — it runs in its own isolate with
/// no access to anything built in `main()`.
@pragma('vm:entry-point')
void _foregroundSyncStartCallback() {
  FlutterForegroundTask.setTaskHandler(_SyncTaskHandler());
}

class _SyncTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  Future<void> _tick() async {
    try {
      await runExportNow();
    } catch (e, stack) {
      developer.log('Foreground sync tick failed: $e', error: e, stackTrace: stack);
    }
  }
}

/// Unique id WorkManager uses to find/replace/cancel the periodic task.
const autoExportTaskName = 'momo_auto_export';

/// How often the background task is allowed to run. 15 minutes is Android's
/// enforced floor for periodic WorkManager tasks — anything shorter gets
/// silently clamped to it anyway. WorkManager still treats this as a
/// minimum, not a guarantee: Android may delay a run to save battery, and
/// the very first run after scheduling isn't guaranteed to be immediate —
/// which is why app launch also services any pending pull directly.
const autoExportInterval = Duration(minutes: 15);

/// Ensures this device has a phone name, registers it with the backend, and
/// turns on the periodic background export — all with no user interaction,
/// so installing the app is enough for it to show up on the dashboard.
///
/// Safe to call on every app start: registration is idempotent (the backend
/// just refreshes `last_seen_at` for a name it already knows) and enabling
/// auto-export is a no-op once it's already scheduled.
Future<void> registerDeviceAndEnableAutoExport() async {
  final settingsService = SettingsService();
  final phoneName = await settingsService.getOrCreateDeviceName();
  final backendUrl = await settingsService.getBackendUrl();

  try {
    await http.post(
      Uri.parse('$backendUrl/api/phones/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': phoneName}),
    );
  } catch (e) {
    developer.log('Device registration failed (will retry on next launch): $e');
  }

  await settingsService.setAutoExportEnabled(true);

  // Each step below is independent — one failing (e.g. WorkManager) must
  // not stop the foreground service, which is the primary sync path, from
  // starting.
  try {
    await enableAutoExport();
  } catch (e) {
    developer.log('Enabling the WorkManager backstop failed: $e');
  }

  // The foreground service is the fast path (polls every 60s, no waiting
  // on a dashboard pull request); WorkManager's 15-minute task is just a
  // backstop in case Android kills the foreground service.
  try {
    await startForegroundSync();
  } catch (e) {
    developer.log('Starting foreground sync failed: $e');
  }
}

/// Registers the periodic background export, or does nothing if one is
/// already scheduled (WorkManager dedupes by [autoExportTaskName]).
Future<void> enableAutoExport() async {
  await Workmanager().registerPeriodicTask(
    autoExportTaskName,
    autoExportTaskName,
    frequency: autoExportInterval,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

Future<void> disableAutoExport() async {
  await Workmanager().cancelByUniqueName(autoExportTaskName);
}

/// Entry point Android calls to run a registered background task. Must be a
/// top-level (or static) function, since it runs in its own isolate with no
/// access to any app state created in `main()`.
@pragma('vm:entry-point')
void backgroundExportCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runExportNow();
      return true;
    } catch (e, stack) {
      developer.log('Auto export failed: $e', error: e, stackTrace: stack);
      // Returning false asks WorkManager to retry with backoff rather than
      // give up after one failure (e.g. phone was offline this cycle).
      return false;
    }
  });
}

/// Exports every SMS since the last successful run (or the phone's entire
/// history, on the very first run), saves the export to a persistent folder on the
/// device, and uploads it to the configured backend — the same pipeline the
/// manual upload button uses, just unattended.
///
/// Also checks whether the dashboard has queued a pull request for this
/// phone and, if so, services that first (it defines its own range).
///
/// Public so it can be called both from the background isolate
/// ([backgroundExportCallbackDispatcher]) and directly from the foreground
/// right after registering, for an immediate first sync.
Future<void> runExportNow() async {
  final settingsService = SettingsService();
  final phoneName = await settingsService.getPhoneName();
  if (phoneName == null || phoneName.isEmpty) {
    developer.log('Auto export skipped: no phone name configured yet');
    return;
  }

  final backendUrl = await settingsService.getBackendUrl();
  await checkAndServicePendingPull(phoneName: phoneName, backendUrl: backendUrl);

  final smsService = SmsService();
  final allMessages = await smsService.getAllMessages();

  // On the very first run, upload the phone's entire SMS history, not just
  // a recent window, so the server has everything from the start.
  final since = await settingsService.getLastAutoExportAt() ?? DateTime(2000);
  final messagesInRange = allMessages.where((m) => m.date.isAfter(since)).toList();

  if (messagesInRange.isEmpty) {
    developer.log('Auto export: no new messages since $since');
    return;
  }

  final documentsDir = await getApplicationDocumentsDirectory();
  final exportsDir = Directory('${documentsDir.path}/momo_exports');

  final exportService = ExportService();
  final zipFile = await exportService.buildZipExport(messagesInRange, directory: exportsDir);

  await UploadService(backendUrl).uploadZip(phoneName: phoneName, zipFile: zipFile);

  // The newest message's own timestamp, not "now", so a device clock that's
  // slightly ahead can't skip over messages that arrive before the next run.
  final newestDate = messagesInRange.map((m) => m.date).reduce((a, b) => a.isAfter(b) ? a : b);
  await settingsService.setLastAutoExportAt(newestDate);

  developer.log('Auto export: uploaded ${messagesInRange.length} message(s)');
}

/// Asks the backend whether the dashboard has queued an export request for
/// this phone ("pull whenever I want, the range I want"), and if so,
/// exports and uploads exactly that range, then reports completion back.
///
/// The phone can't be pushed to directly, so this polling — run from the
/// periodic background task and from the manual upload button, for a fast
/// path when testing or when the user just wants it done now — is what
/// makes the dashboard's "Request pull" button actually do something.
///
/// @returns true if a pending request was found and serviced.
Future<bool> checkAndServicePendingPull({
  required String phoneName,
  required String backendUrl,
}) async {
  final pending = await _fetchPendingPull(backendUrl, phoneName);
  if (pending == null) return false;

  final pullRequestId = pending['id'] as int;
  final startDate = pending['start_date'] != null ? DateTime.parse(pending['start_date'] as String) : null;
  final endDate = pending['end_date'] != null ? DateTime.parse(pending['end_date'] as String) : null;

  try {
    final smsService = SmsService();
    final allMessages = await smsService.getAllMessages();

    final rangeStart = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final messagesInRange = allMessages.where((m) {
      return m.date.isAfter(rangeStart) && (endDate == null || m.date.isBefore(endDate.add(const Duration(days: 1))));
    }).toList();

    if (messagesInRange.isNotEmpty) {
      final documentsDir = await getApplicationDocumentsDirectory();
      final exportsDir = Directory('${documentsDir.path}/momo_exports');
      final exportService = ExportService();
      final zipFile = await exportService.buildZipExport(messagesInRange, directory: exportsDir);
      await UploadService(backendUrl).uploadZip(phoneName: phoneName, zipFile: zipFile);
    }

    await _completePullRequest(backendUrl, pullRequestId, messagesInRange.length, 'completed');
    developer.log('Pull request $pullRequestId serviced: ${messagesInRange.length} message(s)');
    return true;
  } catch (e) {
    await _completePullRequest(backendUrl, pullRequestId, 0, 'failed');
    rethrow;
  }
}

Future<Map<String, dynamic>?> _fetchPendingPull(String backendUrl, String phoneName) async {
  final uri = Uri.parse('$backendUrl/api/phones/by-name/${Uri.encodeComponent(phoneName)}/pending-pull');
  final response = await http.get(uri);
  if (response.statusCode != 200) return null;
  if (response.body.isEmpty || response.body == 'null') return null;
  return jsonDecode(response.body) as Map<String, dynamic>;
}

Future<void> _completePullRequest(String backendUrl, int pullRequestId, int messageCount, String status) async {
  final uri = Uri.parse('$backendUrl/api/pull-requests/$pullRequestId/complete');
  await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'message_count': messageCount, 'status': status}),
  );
}
