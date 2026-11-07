import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

import '../data/local/sindar_database.dart';
import 'backup_archive_codec.dart';

enum CloudSyncSchedule {
  manual,
  automatic,
  daily,
  weekly;

  String get storageValue => name;

  String get titleAr => switch (this) {
        CloudSyncSchedule.manual => 'يدوي فقط',
        CloudSyncSchedule.automatic => 'تلقائي',
        CloudSyncSchedule.daily => 'يومي',
        CloudSyncSchedule.weekly => 'أسبوعي',
      };

  Duration? get frequency => switch (this) {
        CloudSyncSchedule.manual => null,
        CloudSyncSchedule.automatic => const Duration(hours: 6),
        CloudSyncSchedule.daily => const Duration(hours: 24),
        CloudSyncSchedule.weekly => const Duration(days: 7),
      };

  static CloudSyncSchedule fromStorage(String? value) {
    if (value == null || value.trim().isEmpty) {
      return CloudSyncSchedule.manual;
    }
    return CloudSyncSchedule.values.firstWhere(
      (item) => item.storageValue == value,
      orElse: () => CloudSyncSchedule.manual,
    );
  }
}

class CloudSyncStatus {
  const CloudSyncStatus({
    required this.connected,
    required this.schedule,
    this.accountEmail,
    this.lastBackupAt,
    this.lastRestoreAt,
    this.remoteBackupAt,
    this.remoteBackupSize,
    this.lastError,
  });

  final bool connected;
  final String? accountEmail;
  final CloudSyncSchedule schedule;
  final DateTime? lastBackupAt;
  final DateTime? lastRestoreAt;
  final DateTime? remoteBackupAt;
  final int? remoteBackupSize;
  final String? lastError;
}

class CloudBackupResult {
  const CloudBackupResult({
    required this.createdAt,
    required this.remoteFileId,
    required this.size,
  });

  final DateTime createdAt;
  final String remoteFileId;
  final int size;
}

class CloudRestoreResult {
  const CloudRestoreResult({
    required this.backupCreatedAt,
    required this.restoredAt,
    required this.attachmentCount,
  });

  final DateTime backupCreatedAt;
  final DateTime restoredAt;
  final int attachmentCount;
}

class FreeGoogleDriveSyncService {
  FreeGoogleDriveSyncService._();

  static final FreeGoogleDriveSyncService instance =
      FreeGoogleDriveSyncService._();

  static const String _folderName = 'SINDAR_Cloud_Sync';
  static const String _backupFileName = 'sindar_backup.zip';
  static const String _scheduleKey = 'cloud_sync_schedule';
  static const String _lastBackupKey = 'cloud_sync_last_backup_at';
  static const String _lastRestoreKey = 'cloud_sync_last_restore_at';
  static const String _lastErrorKey = 'cloud_sync_last_error';
  static const String _lastRemoteIdKey = 'cloud_sync_remote_file_id';
  static const String _connectedOnceKey = 'cloud_sync_connected_once';

  /// Public Google OAuth Web client identifier for SINDAR Android.
  /// Shared by every installation; each customer authorizes their own Drive.
  /// Override at build time only when changing the Google Cloud project.
  static const String googleOAuthWebClientId = String.fromEnvironment(
    'SINDAR_GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '626355862977-c96iop9plh9ekjned86pac908u2ash81.apps.googleusercontent.com',
  );

  GoogleSignIn? _googleSignIn;

  Future<GoogleSignIn> _configuredSignIn() async {
    return _googleSignIn ??= GoogleSignIn(
      scopes: const <String>[drive.DriveApi.driveAppdataScope],
      serverClientId: googleOAuthWebClientId,
    );
  }

  Future<GoogleSignInAccount?> connect() async {
    try {
      await _requiredBackupKeyMaterial();
      final signIn = await _configuredSignIn();
      final account = signIn.currentUser ?? await signIn.signIn();
      if (account == null) {
        return null;
      }
      final client = await signIn.authenticatedClient();
      if (client == null) {
        throw const FormatException(
          'لم يمنح حساب Google صلاحية Drive المطلوبة.',
        );
      }
      client.close();
      await SindarDatabase.instance.saveSetting(
        _connectedOnceKey,
        'true',
      );
      final storedSchedule = await SindarDatabase.instance.getSetting(
        _scheduleKey,
      );
      if (storedSchedule == null || storedSchedule.trim().isEmpty) {
        await setSchedule(CloudSyncSchedule.automatic);
      }
      await _clearLastError();
      return account;
    } catch (error) {
      final friendly = _friendlyGoogleError(error);
      await _saveLastError(friendly);
      throw FormatException(friendly);
    }
  }

  Future<void> disconnect() async {
    final signIn = await _configuredSignIn();
    try {
      await signIn.disconnect();
    } on Object {
      await signIn.signOut();
    }
    await SindarDatabase.instance.saveSetting(
      _connectedOnceKey,
      'false',
    );
    await setSchedule(CloudSyncSchedule.manual);
  }

  Future<CloudSyncStatus> status({
    bool refreshRemote = false,
  }) async {
    final schedule = CloudSyncSchedule.fromStorage(
      await SindarDatabase.instance.getSetting(_scheduleKey),
    );
    final lastBackupAt = _parseUtc(
      await SindarDatabase.instance.getSetting(_lastBackupKey),
    );
    final lastRestoreAt = _parseUtc(
      await SindarDatabase.instance.getSetting(_lastRestoreKey),
    );
    final lastError = await SindarDatabase.instance.getSetting(_lastErrorKey);

    final connectedOnce = await SindarDatabase.instance.getSetting(
      _connectedOnceKey,
    );
    if (connectedOnce != 'true') {
      return CloudSyncStatus(
        connected: false,
        schedule: schedule,
        lastBackupAt: lastBackupAt,
        lastRestoreAt: lastRestoreAt,
        lastError: lastError?.trim().isEmpty == true ? null : lastError,
      );
    }

    GoogleSignInAccount? account;
    try {
      final signIn = await _configuredSignIn();
      account = signIn.currentUser;
      account ??= await signIn.signInSilently();
    } catch (error) {
      final friendly = _friendlyGoogleError(error);
      await _saveLastError(friendly);
      return CloudSyncStatus(
        connected: false,
        schedule: schedule,
        lastBackupAt: lastBackupAt,
        lastRestoreAt: lastRestoreAt,
        lastError: friendly,
      );
    }

    DateTime? remoteAt;
    int? remoteSize;
    if (refreshRemote && account != null) {
      try {
        final session = await _openDriveSession(
          interactiveSignIn: false,
        );
        if (session != null) {
          try {
            final folderId = await _ensureSyncFolder(session.api);
            final remote = await _findRemoteBackup(
              session.api,
              folderId,
            );
            remoteAt = remote?.modifiedTime?.toUtc();
            remoteSize = int.tryParse(remote?.size ?? '');
          } finally {
            session.close();
          }
        }
      } on Object {
        // A temporary network failure must not make the status screen unusable.
      }
    }

    return CloudSyncStatus(
      connected: account != null,
      accountEmail: account?.email,
      schedule: schedule,
      lastBackupAt: lastBackupAt,
      lastRestoreAt: lastRestoreAt,
      remoteBackupAt: remoteAt,
      remoteBackupSize: remoteSize,
      lastError: lastError?.trim().isEmpty == true ? null : lastError,
    );
  }

  Future<CloudBackupResult> backupNow({
    bool interactiveSignIn = true,
  }) async {
    final keyMaterial = await _requiredBackupKeyMaterial();
    final session = await _openDriveSession(
      interactiveSignIn: interactiveSignIn,
    );
    if (session == null) {
      throw const FormatException(
        'تعذر تسجيل الدخول إلى Google Drive.',
      );
    }

    io.File? temporaryBackup;
    try {
      final databaseBytes = await _readConsistentDatabase();
      final attachments = await _readAttachments();
      final encoded = await SindarBackupCodec.encode(
        databaseBytes: databaseBytes,
        attachments: attachments,
        licenseKeyMaterial: keyMaterial,
      );

      final tempDir = await getTemporaryDirectory();
      temporaryBackup = io.File(
        p.join(tempDir.path, _backupFileName),
      );
      await temporaryBackup.writeAsBytes(encoded, flush: true);

      final folderId = await _ensureSyncFolder(session.api);
      final existing = await _findRemoteBackup(session.api, folderId);
      final media = drive.Media(
        Stream<List<int>>.value(encoded),
        encoded.length,
        contentType: 'application/zip',
      );

      drive.File uploaded;
      if (existing?.id != null) {
        uploaded = await session.api.files.update(
          drive.File()
            ..name = _backupFileName
            ..appProperties = <String, String>{
              'sindarFormat': '1',
              'keyId': SindarBackupCodec.keyIdForToken(keyMaterial),
            },
          existing!.id!,
          uploadMedia: media,
          $fields: 'id,name,modifiedTime,size',
        );
      } else {
        uploaded = await session.api.files.create(
          drive.File()
            ..name = _backupFileName
            ..parents = <String>[folderId]
            ..mimeType = 'application/zip'
            ..appProperties = <String, String>{
              'sindarFormat': '1',
              'keyId': SindarBackupCodec.keyIdForToken(keyMaterial),
            },
          uploadMedia: media,
          $fields: 'id,name,modifiedTime,size',
        );
      }

      final now = DateTime.now().toUtc();
      await SindarDatabase.instance.saveSetting(
        _lastBackupKey,
        now.toIso8601String(),
      );
      if (uploaded.id != null) {
        await SindarDatabase.instance.saveSetting(
          _lastRemoteIdKey,
          uploaded.id!,
        );
      }
      await _clearLastError();

      return CloudBackupResult(
        createdAt: now,
        remoteFileId: uploaded.id ?? existing?.id ?? '',
        size: encoded.length,
      );
    } catch (error) {
      await _saveLastError(_friendlyGoogleError(error));
      rethrow;
    } finally {
      session.close();
      if (temporaryBackup != null && await temporaryBackup.exists()) {
        await temporaryBackup.delete();
      }
    }
  }

  Future<CloudRestoreResult> restoreLatest({
    bool interactiveSignIn = true,
  }) async {
    final keyMaterial = await _requiredBackupKeyMaterial();
    final session = await _openDriveSession(
      interactiveSignIn: interactiveSignIn,
    );
    if (session == null) {
      throw const FormatException(
        'تعذر تسجيل الدخول إلى Google Drive.',
      );
    }

    try {
      final folderId = await _ensureSyncFolder(session.api);
      final remote = await _findRemoteBackup(session.api, folderId);
      final remoteId = remote?.id;
      if (remoteId == null) {
        throw const FormatException(
          'لا توجد نسخة احتياطية لسندار في Google Drive.',
        );
      }

      final response = await session.api.files.get(
        remoteId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (response is! drive.Media) {
        throw const FormatException(
          'تعذر تنزيل ملف النسخة الاحتياطية.',
        );
      }
      final downloaded = await response.stream.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );

      final decoded = await SindarBackupCodec.decode(
        backupBytes: Uint8List.fromList(downloaded),
        licenseKeyMaterial: keyMaterial,
      );
      await _validateStagedDatabase(decoded.databaseBytes);

      final preservedLicense = <String, String?>{
        'license_token':
            await SindarDatabase.instance.getSetting('license_token'),
        'license_grant':
            await SindarDatabase.instance.getSetting('license_grant'),
        'license_policy':
            await SindarDatabase.instance.getSetting('license_policy'),
      };

      await _replaceLocalData(decoded);

      for (final entry in preservedLicense.entries) {
        final value = entry.value;
        if (value != null && value.isNotEmpty) {
          await SindarDatabase.instance.saveSetting(entry.key, value);
        }
      }

      final restoredAt = DateTime.now().toUtc();
      await SindarDatabase.instance.saveSetting(
        _lastRestoreKey,
        restoredAt.toIso8601String(),
      );
      await _clearLastError();

      return CloudRestoreResult(
        backupCreatedAt: decoded.createdAt,
        restoredAt: restoredAt,
        attachmentCount: decoded.attachments.length,
      );
    } catch (error) {
      await _saveLastError(_friendlyGoogleError(error));
      rethrow;
    } finally {
      session.close();
    }
  }

  Future<void> setSchedule(CloudSyncSchedule schedule) async {
    await SindarDatabase.instance.saveSetting(
      _scheduleKey,
      schedule.storageValue,
    );
    await CloudSyncScheduler.apply(schedule);
  }

  Future<String> _requiredBackupKeyMaterial() async {
    final token = await SindarDatabase.instance.getSetting('license_token');
    if (token == null || token.trim().isEmpty) {
      throw const FormatException(
        'فعّل ترخيص سندار أولاً قبل النسخ أو الاستعادة.',
      );
    }
    final policy = await SindarDatabase.instance.getLicensePolicy();
    if (policy.customerId.trim().isEmpty) {
      throw const FormatException(
        'هوية الترخيص غير متاحة لإنشاء مفتاح النسخة.',
      );
    }
    return policy.customerId.trim();
  }

  Future<_DriveSession?> _openDriveSession({
    required bool interactiveSignIn,
  }) async {
    final signIn = await _configuredSignIn();
    GoogleSignInAccount? account = signIn.currentUser;
    try {
      account ??= await signIn.signInSilently();
      if (account == null && interactiveSignIn) {
        account = await signIn.signIn();
      }
    } catch (error) {
      throw FormatException(_friendlyGoogleError(error));
    }
    if (account == null) {
      return null;
    }

    dynamic client;
    try {
      client = await signIn.authenticatedClient();
    } catch (error) {
      throw FormatException(_friendlyGoogleError(error));
    }
    if (client == null) {
      if (!interactiveSignIn) return null;
      throw const FormatException(
        'تعذر الحصول على صلاحية Google Drive. أعد ربط الحساب.',
      );
    }

    return _DriveSession(
      account: account,
      client: client,
      api: drive.DriveApi(client),
    );
  }

  Future<String> _ensureSyncFolder(drive.DriveApi api) async {
    final listed = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_folderName' and "
          "mimeType = 'application/vnd.google-apps.folder' and "
          'trashed = false',
      $fields: 'files(id,name)',
    );
    final existing = listed.files?.where((item) => item.id != null).toList() ??
        const <drive.File>[];
    if (existing.isNotEmpty) {
      return existing.first.id!;
    }

    final created = await api.files.create(
      drive.File()
        ..name = _folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = const <String>['appDataFolder']
        ..appProperties = const <String, String>{
          'sindar': 'cloud-sync',
        },
      $fields: 'id,name',
    );
    if (created.id == null) {
      throw const FormatException(
        'تعذر إنشاء مجلد SINDAR_Cloud_Sync.',
      );
    }
    return created.id!;
  }

  Future<drive.File?> _findRemoteBackup(
    drive.DriveApi api,
    String folderId,
  ) async {
    final listed = await api.files.list(
      spaces: 'appDataFolder',
      q: "'$folderId' in parents and "
          "name = '$_backupFileName' and trashed = false",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id,name,modifiedTime,size,appProperties)',
    );
    final files = listed.files;
    return files == null || files.isEmpty ? null : files.first;
  }

  Future<Uint8List> _readConsistentDatabase() async {
    final db = await SindarDatabase.instance.database;
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    await SindarDatabase.instance.close();

    final dbFile = io.File(await _databasePath());
    if (!await dbFile.exists()) {
      await SindarDatabase.instance.database;
      throw const FormatException('قاعدة بيانات سندار غير موجودة.');
    }

    try {
      return Uint8List.fromList(await dbFile.readAsBytes());
    } finally {
      await SindarDatabase.instance.database;
    }
  }

  Future<Map<String, Uint8List>> _readAttachments() async {
    final root = await attachmentsDirectory();
    if (!await root.exists()) {
      await root.create(recursive: true);
      return <String, Uint8List>{};
    }

    final result = <String, Uint8List>{};
    await for (final entity in root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! io.File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      result[relative] = Uint8List.fromList(
        await entity.readAsBytes(),
      );
    }
    return result;
  }

  Future<void> _validateStagedDatabase(Uint8List databaseBytes) async {
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final file = io.File(
      p.join(
        temp.path,
        'sindar-restore-check-$stamp.db',
      ),
    );
    await file.writeAsBytes(databaseBytes, flush: true);

    Database? testDb;
    try {
      testDb = await openDatabase(
        file.path,
        readOnly: true,
      );
      final result = await testDb.rawQuery('PRAGMA integrity_check');
      final value = result.isEmpty ? null : result.first.values.first;
      if (value?.toString().toLowerCase() != 'ok') {
        throw const FormatException(
          'فشل فحص سلامة قاعدة البيانات داخل النسخة.',
        );
      }
    } finally {
      await testDb?.close();
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _replaceLocalData(SindarBackupPayload payload) async {
    final databasePath = await _databasePath();
    final databaseFile = io.File(databasePath);
    final rollbackFile = io.File('$databasePath.pre_restore');
    final walFile = io.File('$databasePath-wal');
    final shmFile = io.File('$databasePath-shm');

    final attachments = await attachmentsDirectory();
    final attachmentsParent = attachments.parent;
    final rollbackAttachments = io.Directory(
      p.join(
        attachmentsParent.path,
        'sindar_attachments.pre_restore',
      ),
    );

    await SindarDatabase.instance.close();

    try {
      if (await rollbackFile.exists()) {
        await rollbackFile.delete();
      }
      if (await databaseFile.exists()) {
        await databaseFile.copy(rollbackFile.path);
      }
      if (await walFile.exists()) await walFile.delete();
      if (await shmFile.exists()) await shmFile.delete();

      await databaseFile.writeAsBytes(
        payload.databaseBytes,
        flush: true,
      );

      if (await rollbackAttachments.exists()) {
        await rollbackAttachments.delete(recursive: true);
      }
      if (await attachments.exists()) {
        await attachments.rename(rollbackAttachments.path);
      }
      await attachments.create(recursive: true);

      for (final entry in payload.attachments.entries) {
        final target = io.File(
          p.joinAll(
            <String>[
              attachments.path,
              ...entry.key.split('/'),
            ],
          ),
        );
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value, flush: true);
      }

      final restoredDb = await SindarDatabase.instance.database;
      final integrity = await restoredDb.rawQuery('PRAGMA integrity_check');
      final value = integrity.isEmpty ? null : integrity.first.values.first;
      if (value?.toString().toLowerCase() != 'ok') {
        throw const FormatException(
          'فشل فحص قاعدة البيانات بعد الاستعادة.',
        );
      }

      if (await rollbackFile.exists()) {
        await rollbackFile.delete();
      }
      if (await rollbackAttachments.exists()) {
        await rollbackAttachments.delete(recursive: true);
      }
    } catch (_) {
      await SindarDatabase.instance.close();
      if (await rollbackFile.exists()) {
        await rollbackFile.copy(databaseFile.path);
      }
      if (await attachments.exists()) {
        await attachments.delete(recursive: true);
      }
      if (await rollbackAttachments.exists()) {
        await rollbackAttachments.rename(attachments.path);
      }
      await SindarDatabase.instance.database;
      rethrow;
    }
  }

  static Future<io.Directory> attachmentsDirectory() async {
    final support = await getApplicationSupportDirectory();
    return io.Directory(
      p.join(support.path, 'sindar_attachments'),
    );
  }

  static Future<String> _databasePath() async {
    final root = await getDatabasesPath();
    return p.join(root, 'sindar.db');
  }

  Future<void> _saveLastError(String message) {
    return SindarDatabase.instance.saveSetting(
      _lastErrorKey,
      message,
    );
  }

  Future<void> _clearLastError() {
    return SindarDatabase.instance.saveSetting(
      _lastErrorKey,
      '',
    );
  }

  static DateTime? _parseUtc(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  static String _friendlyGoogleError(Object error) {
    final text = error.toString();
    if (text.contains('ApiException: 10') ||
        text.contains('DEVELOPER_ERROR') ||
        text.contains('sign_in_failed')) {
      return 'ربط Google مرفوض لأن OAuth غير مطابق لهذه النسخة. '
          'يجب تسجيل الحزمة com.sindar.sindar_app وSHA-1 لشهادة APK النهائية '
          'في Google Cloud ثم تفعيل Google Drive API.';
    }
    if (text.contains('ApiException: 12500') ||
        text.contains('SIGN_IN_CANCELLED')) {
      return 'تم إلغاء تسجيل الدخول إلى Google.';
    }
    if (text.contains('SocketException') ||
        text.contains('network_error')) {
      return 'تعذر الاتصال بخدمات Google. تحقق من الإنترنت ثم أعد المحاولة.';
    }
    return text
        .replaceFirst('FormatException: ', '')
        .replaceFirst('Exception: ', '');
  }
}

class CloudSyncScheduler {
  CloudSyncScheduler._();

  static const String taskName = 'sindar.google_drive.backup';
  static const String uniqueName = 'sindar-google-drive-periodic-backup';

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(sindarCloudSyncCallbackDispatcher);
    _initialized = true;
  }

  static Future<void> restoreRegistration() async {
    await initialize();
    final token = await SindarDatabase.instance.getSetting('license_token');
    final connected = await SindarDatabase.instance.getSetting(
      FreeGoogleDriveSyncService._connectedOnceKey,
    );
    if (token == null || token.trim().isEmpty || connected != 'true') {
      await apply(CloudSyncSchedule.manual);
      return;
    }
    final stored = await SindarDatabase.instance.getSetting(
      FreeGoogleDriveSyncService._scheduleKey,
    );
    final schedule = CloudSyncSchedule.fromStorage(stored);
    if (schedule != CloudSyncSchedule.manual) {
      await apply(schedule);
    }
  }

  static Future<void> apply(CloudSyncSchedule schedule) async {
    await initialize();
    await Workmanager().cancelByUniqueName(uniqueName);
    final frequency = schedule.frequency;
    if (frequency == null) return;

    await Workmanager().registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
}

@pragma('vm:entry-point')
void sindarCloudSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != CloudSyncScheduler.taskName) {
      return true;
    }

    try {
      final schedule = CloudSyncSchedule.fromStorage(
        await SindarDatabase.instance.getSetting(
          FreeGoogleDriveSyncService._scheduleKey,
        ),
      );
      if (schedule == CloudSyncSchedule.manual) {
        return true;
      }
      final status = await FreeGoogleDriveSyncService.instance.status();
      if (!status.connected) {
        return true;
      }
      await FreeGoogleDriveSyncService.instance.backupNow(
        interactiveSignIn: false,
      );
      return true;
    } on Object {
      return false;
    }
  });
}

class _DriveSession {
  const _DriveSession({
    required this.account,
    required this.client,
    required this.api,
  });

  final GoogleSignInAccount account;
  final dynamic client;
  final drive.DriveApi api;

  void close() {
    client.close();
  }
}
