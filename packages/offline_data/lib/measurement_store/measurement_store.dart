import 'dart:convert';

import 'package:biometric_estimators/biometric_estimators.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sensor_availability/sensor_availability.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

const String _kDefaultDbName = 'measurements.db';

class MeasurementStore implements BiometricMeasurementRepository {
  MeasurementStore._(this._db);

  final Database _db;

  static Future<MeasurementStore> open({String? path}) async {
    final String dbPath;
    if (path == inMemoryDatabasePath) {
      dbPath = inMemoryDatabasePath;
    } else if (path != null && p.isAbsolute(path)) {
      dbPath = path;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      dbPath = p.join(dir.path, path ?? _kDefaultDbName);
    }
    final Database db = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (Database db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL;');
        await db.rawQuery('PRAGMA synchronous=NORMAL;');
      },
      onCreate: _createSchema,
    );
    return MeasurementStore._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS measurements(
        id              TEXT PRIMARY KEY,
        biometric_id    TEXT NOT NULL,
        captured_at     INTEGER NOT NULL,
        duration_ms     INTEGER NOT NULL,
        primary_value   REAL,
        primary_unit    TEXT,
        primary_label   TEXT,
        confidence      REAL,
        status          TEXT NOT NULL,
        payload_json    TEXT NOT NULL,
        schema_version  INTEGER NOT NULL
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS measurements_by_biometric_time
        ON measurements(biometric_id, captured_at DESC);
    ''');
  }

  @override
  Future<void> insert(BiometricMeasurement measurement) async {
    final Map<String, dynamic> payload = measurement.toLLMRecord();
    await _db.insert('measurements', <String, Object?>{
      'id': const Uuid().v4(),
      'biometric_id': measurement.id.name,
      'captured_at': measurement.capturedAt.toUtc().millisecondsSinceEpoch,
      'duration_ms': measurement.duration.inMilliseconds,
      'primary_value': measurement.primary?.value,
      'primary_unit': measurement.primary?.unit,
      'primary_label': measurement.primary?.label,
      'confidence': measurement.confidence,
      'status': measurement.status.name,
      'payload_json': jsonEncode(payload),
      'schema_version': BiometricMeasurement.schemaVersion,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<BiometricMeasurement?> latestFor(BiometricId id) async {
    final List<BiometricMeasurement> history = await historyFor(id, limit: 1);
    return history.isEmpty ? null : history.first;
  }

  @override
  Future<List<BiometricMeasurement>> historyFor(
    BiometricId id, {
    int limit = 50,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'measurements',
      columns: <String>['payload_json'],
      where: 'biometric_id = ?',
      whereArgs: <Object>[id.name],
      orderBy: 'captured_at DESC',
      limit: limit,
    );
    return rows.map(_measurementFromRow).toList(growable: false);
  }

  Future<List<BiometricMeasurement>> recentAll({int limit = 100}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'measurements',
      columns: <String>['payload_json'],
      orderBy: 'captured_at DESC',
      limit: limit,
    );
    return rows.map(_measurementFromRow).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> exportLLMBundle({DateTime? since}) async {
    final List<Map<String, Object?>> rows;
    if (since == null) {
      rows = await _db.query(
        'measurements',
        columns: <String>['payload_json'],
        orderBy: 'captured_at DESC',
      );
    } else {
      rows = await _db.query(
        'measurements',
        columns: <String>['payload_json'],
        where: 'captured_at >= ?',
        whereArgs: <Object>[since.toUtc().millisecondsSinceEpoch],
        orderBy: 'captured_at DESC',
      );
    }
    return rows.map(_payloadFromRow).toList(growable: false);
  }

  Future<void> close() async {
    await _db.close();
  }

  static BiometricMeasurement _measurementFromRow(Map<String, Object?> row) {
    return BiometricMeasurement.fromLLMRecord(_payloadFromRow(row));
  }

  static Map<String, dynamic> _payloadFromRow(Map<String, Object?> row) {
    return jsonDecode(row['payload_json']! as String) as Map<String, dynamic>;
  }
}
