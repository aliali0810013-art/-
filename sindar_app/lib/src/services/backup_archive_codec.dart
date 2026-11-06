import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class SindarBackupPayload {
  const SindarBackupPayload({
    required this.databaseBytes,
    required this.attachments,
    required this.createdAt,
  });

  final Uint8List databaseBytes;
  final Map<String, Uint8List> attachments;
  final DateTime createdAt;
}

class SindarBackupCodec {
  SindarBackupCodec._();

  static const int formatVersion = 1;
  static const String databaseEntry = 'database/sindar.db';
  static const String manifestEntry = 'manifest.json';
  static const String encryptedPayloadEntry = 'payload.enc';

  static final AesGcm _cipher = AesGcm.with256bits();

  static String keyIdForToken(String licenseKeyMaterial) {
    final digest = sha256.convert(utf8.encode(licenseKeyMaterial.trim())).toString();
    return digest.substring(0, 16);
  }

  static Future<Uint8List> encode({
    required Uint8List databaseBytes,
    required Map<String, Uint8List> attachments,
    required String licenseKeyMaterial,
    DateTime? createdAt,
  }) async {
    _validateSqlite(databaseBytes);
    final token = licenseKeyMaterial.trim();
    if (token.isEmpty) {
      throw const FormatException(
        'يجب تفعيل ترخيص سندار قبل إنشاء نسخة مشفرة.',
      );
    }

    final inner = Archive()
      ..addFile(ArchiveFile.bytes(databaseEntry, databaseBytes));

    for (final entry in attachments.entries) {
      final safeName = _sanitizeAttachmentName(entry.key);
      inner.addFile(
        ArchiveFile.bytes('attachments/$safeName', entry.value),
      );
    }

    final compressedPayload = ZipEncoder().encode(inner);
    final secretKey = await _secretKeyForToken(token);
    final secretBox = await _cipher.encrypt(
      compressedPayload,
      secretKey: secretKey,
    );
    final encrypted = Uint8List.fromList(secretBox.concatenation());

    final timestamp = (createdAt ?? DateTime.now().toUtc()).toUtc();
    final manifest = <String, Object?>{
      'format': 'SINDAR_BACKUP',
      'version': formatVersion,
      'createdAt': timestamp.toIso8601String(),
      'keyId': keyIdForToken(token),
      'cipher': 'AES-256-GCM',
      'payloadSha256': sha256.convert(encrypted).toString(),
      'databaseBytes': databaseBytes.length,
      'attachmentCount': attachments.length,
    };

    final outer = Archive()
      ..addFile(
        ArchiveFile.string(
          manifestEntry,
          jsonEncode(manifest),
        ),
      )
      ..addFile(
        ArchiveFile.bytes(
          encryptedPayloadEntry,
          encrypted,
        ),
      );

    return Uint8List.fromList(ZipEncoder().encode(outer));
  }

  static Future<SindarBackupPayload> decode({
    required Uint8List backupBytes,
    required String licenseKeyMaterial,
  }) async {
    final token = licenseKeyMaterial.trim();
    if (token.isEmpty) {
      throw const FormatException(
        'فعّل نفس ترخيص سندار المستخدم في النسخة قبل الاستعادة.',
      );
    }

    final outer = ZipDecoder().decodeBytes(
      backupBytes,
      verify: true,
      throwOnError: true,
    );
    final manifestFile = outer.findFile(manifestEntry);
    final payloadFile = outer.findFile(encryptedPayloadEntry);
    if (manifestFile == null || payloadFile == null) {
      throw const FormatException('ملف النسخة الاحتياطية غير صالح.');
    }

    final manifestBytes = manifestFile.readBytes();
    final encryptedBytes = payloadFile.readBytes();
    if (manifestBytes == null || encryptedBytes == null) {
      throw const FormatException('تعذر قراءة محتوى النسخة الاحتياطية.');
    }

    final decodedManifest = jsonDecode(utf8.decode(manifestBytes));
    if (decodedManifest is! Map<String, dynamic>) {
      throw const FormatException('بيانات تعريف النسخة غير صالحة.');
    }
    if (decodedManifest['format'] != 'SINDAR_BACKUP' ||
        decodedManifest['version'] != formatVersion) {
      throw const FormatException('إصدار النسخة الاحتياطية غير مدعوم.');
    }
    if (decodedManifest['keyId'] != keyIdForToken(token)) {
      throw const FormatException(
        'هذه النسخة مشفرة بترخيص سندار مختلف.',
      );
    }

    final expectedPayloadHash = decodedManifest['payloadSha256'] as String?;
    final actualPayloadHash = sha256.convert(encryptedBytes).toString();
    if (expectedPayloadHash == null ||
        expectedPayloadHash != actualPayloadHash) {
      throw const FormatException(
        'تم اكتشاف تلف أو تعديل في ملف النسخة الاحتياطية.',
      );
    }

    final secretKey = await _secretKeyForToken(token);
    final secretBox = SecretBox.fromConcatenation(
      encryptedBytes,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
      copy: false,
    );

    List<int> clearPayload;
    try {
      clearPayload = await _cipher.decrypt(
        secretBox,
        secretKey: secretKey,
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'تعذر فك تشفير النسخة الاحتياطية أو أنها تالفة.',
      );
    }

    final inner = ZipDecoder().decodeBytes(
      clearPayload,
      verify: true,
      throwOnError: true,
    );
    final databaseFile = inner.findFile(databaseEntry);
    final databaseBytes = databaseFile?.readBytes();
    if (databaseBytes == null) {
      throw const FormatException('قاعدة بيانات سندار غير موجودة في النسخة.');
    }
    _validateSqlite(databaseBytes);

    final attachments = <String, Uint8List>{};
    for (final file in inner.files) {
      if (file.isDirectory || !file.name.startsWith('attachments/')) {
        continue;
      }
      final relative = file.name.substring('attachments/'.length);
      final safeName = _sanitizeAttachmentName(relative);
      final bytes = file.readBytes();
      if (bytes != null) {
        attachments[safeName] = Uint8List.fromList(bytes);
      }
    }

    final createdAtRaw = decodedManifest['createdAt'] as String?;
    return SindarBackupPayload(
      databaseBytes: Uint8List.fromList(databaseBytes),
      attachments: attachments,
      createdAt: DateTime.tryParse(createdAtRaw ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static Future<SecretKey> _secretKeyForToken(String token) async {
    final digest = sha256.convert(
      utf8.encode('SINDAR-BACKUP-V1|SINDAR-2026|$token'),
    );
    return SecretKey(digest.bytes);
  }

  static String _sanitizeAttachmentName(String raw) {
    final normalized = raw.replaceAll('\\', '/').trim();
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized.contains('../') ||
        normalized == '..') {
      throw const FormatException('اسم مرفق غير آمن داخل النسخة.');
    }
    return normalized;
  }

  static void _validateSqlite(List<int> bytes) {
    const header = <int>[
      0x53,
      0x51,
      0x4c,
      0x69,
      0x74,
      0x65,
      0x20,
      0x66,
      0x6f,
      0x72,
      0x6d,
      0x61,
      0x74,
      0x20,
      0x33,
      0x00,
    ];
    if (bytes.length < header.length) {
      throw const FormatException('ملف قاعدة البيانات غير صالح.');
    }
    for (var i = 0; i < header.length; i++) {
      if (bytes[i] != header[i]) {
        throw const FormatException('ملف قاعدة البيانات ليس SQLite صالحاً.');
      }
    }
  }
}
