import 'dart:convert';

import 'homography.dart';
import 'mold_outline.dart';

/// One finished scan: what was measured, when, and a small picture of it.
class ScanRecord {
  final String id;
  final DateTime date;
  final String name;
  final MoldOutline outline;

  /// Small JPEG of the top-down preview with the outline, base64; may be
  /// empty.
  final String thumbJpegBase64;

  /// How the scale was set (tape or QR), shown with the record.
  final String note;

  const ScanRecord({
    required this.id,
    required this.date,
    required this.name,
    required this.outline,
    this.thumbJpegBase64 = '',
    this.note = '',
  });
}

/// JSON of the scan history. Like the saved molds, storage is outside the
/// app's control, so each record is validated on its own and a bad one is
/// skipped instead of losing the history.
class ScanHistoryCodec {
  static const maxRecords = 40;
  static const maxPoints = 20000;
  static const maxSizeMm = 10000.0;
  static const maxThumbChars = 200000;
  static const maxTextLength = 300;
  static const _maxEpochMs = 8640000000000000;

  static List<ScanRecord>? decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (json is! List) return null;
    return [
      for (final e in json.take(maxRecords))
        if (_record(e) case final ScanRecord r) r,
    ];
  }

  static String _text(Object? v) {
    if (v is! String) return '';
    return v.length > maxTextLength ? v.substring(0, maxTextLength) : v;
  }

  static ScanRecord? _record(Object? e) {
    if (e is! Map) return null;
    final id = e['id'], ms = e['date'], pts = e['pts'], thumb = e['thumb'];
    if (id is! String || id.isEmpty || id.length > 64) return null;
    // DateTime throws beyond +-8.64e15 ms: one such record used to make the
    // whole history unreadable, and the next scan then overwrote it.
    if (ms is! int || ms.abs() > _maxEpochMs || pts is! List) return null;
    if (pts.length < 3 || pts.length > maxPoints) return null;
    final points = <Point2D>[];
    for (final p in pts) {
      if (p is! List || p.length != 2) return null;
      final x = p[0], y = p[1];
      if (x is! num || y is! num) return null;
      final dx = x.toDouble(), dy = y.toDouble();
      if (!dx.isFinite || !dy.isFinite) return null;
      if (dx.abs() > maxSizeMm || dy.abs() > maxSizeMm) return null;
      points.add(Point2D(dx, dy));
    }
    final outline = MoldOutline(points);
    if (outline.width < 1 || outline.height < 1) return null;
    final thumbText = thumb is String && thumb.length <= maxThumbChars
        ? thumb
        : '';
    return ScanRecord(
      id: id,
      date: DateTime.fromMillisecondsSinceEpoch(ms),
      name: _text(e['name']),
      outline: outline,
      thumbJpegBase64: thumbText,
      note: _text(e['note']),
    );
  }

  static String encode(List<ScanRecord> records) => jsonEncode([
    for (final r in records.take(maxRecords))
      {
        'id': r.id,
        'date': r.date.millisecondsSinceEpoch,
        'name': r.name,
        'note': r.note,
        'thumb': r.thumbJpegBase64,
        'pts': [
          for (final p in r.outline.points)
            [
              double.parse(p.x.toStringAsFixed(2)),
              double.parse(p.y.toStringAsFixed(2)),
            ],
        ],
      },
  ]);
}
