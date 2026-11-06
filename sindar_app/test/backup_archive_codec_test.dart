import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sindar_app/src/services/backup_archive_codec.dart';

void main() {
  Uint8List fakeSqlite([int extra = 64]) {
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
    return Uint8List.fromList(
      <int>[
        ...header,
        ...List<int>.generate(extra, (index) => index % 251),
      ],
    );
  }

  test('backup codec round-trips SQLite and attachments with AES-GCM', () async {
    final database = fakeSqlite();
    final attachments = <String, Uint8List>{
      'branding/logo.png': Uint8List.fromList(<int>[1, 2, 3, 4]),
      'stamp/company.webp': Uint8List.fromList(<int>[9, 8, 7]),
    };

    final encoded = await SindarBackupCodec.encode(
      databaseBytes: database,
      attachments: attachments,
      licenseKeyMaterial: 'LIC-10001',
      createdAt: DateTime.utc(2026, 11, 7, 2, 30),
    );

    final decoded = await SindarBackupCodec.decode(
      backupBytes: encoded,
      licenseKeyMaterial: 'LIC-10001',
    );

    expect(decoded.databaseBytes, orderedEquals(database));
    expect(
      decoded.attachments['branding/logo.png'],
      orderedEquals(<int>[1, 2, 3, 4]),
    );
    expect(
      decoded.attachments['stamp/company.webp'],
      orderedEquals(<int>[9, 8, 7]),
    );
    expect(decoded.createdAt, DateTime.utc(2026, 11, 7, 2, 30));
  });

  test('backup cannot be restored by a different license identity', () async {
    final encoded = await SindarBackupCodec.encode(
      databaseBytes: fakeSqlite(),
      attachments: const <String, Uint8List>{},
      licenseKeyMaterial: 'LIC-A',
    );

    expect(
      () => SindarBackupCodec.decode(
        backupBytes: encoded,
        licenseKeyMaterial: 'LIC-B',
      ),
      throwsFormatException,
    );
  });

  test('backup rejects unsafe attachment paths', () async {
    expect(
      () => SindarBackupCodec.encode(
        databaseBytes: fakeSqlite(),
        attachments: <String, Uint8List>{
          '../outside.png': Uint8List.fromList(<int>[1]),
        },
        licenseKeyMaterial: 'LIC-A',
      ),
      throwsFormatException,
    );
  });

  test('backup rejects non-SQLite payloads before upload', () async {
    expect(
      () => SindarBackupCodec.encode(
        databaseBytes: Uint8List.fromList(<int>[1, 2, 3]),
        attachments: const <String, Uint8List>{},
        licenseKeyMaterial: 'LIC-A',
      ),
      throwsFormatException,
    );
  });
}
