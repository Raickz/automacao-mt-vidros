import 'dart:convert';

import 'homography.dart';
import 'mold_outline.dart';

/// A mold the worker saved ("MEUS"), kept in this browser's localStorage.
class SavedMold {
  final String id;
  final String name;
  final MoldOutline outline;

  const SavedMold(this.id, this.name, this.outline);
}

/// JSON of the saved molds, kept apart from the browser storage so it can
/// be tested. Storage is outside the app's control (another tab, an old
/// version, an extension, a user editing it by hand), so reading is
/// defensive: each mold is checked on its own and a bad one is skipped
/// instead of losing all of them.
class SavedMoldCodec {
  /// Largest outline accepted: a 6 x 6 m piece is already beyond any glass
  /// sheet; anything bigger is not a real mold.
  static const maxSizeMm = 10000.0;
  static const maxPoints = 20000;
  static const maxNameLength = 200;

  /// The molds in [raw], or null when [raw] is not a JSON list at all (so the
  /// caller can keep it instead of overwriting it).
  static List<SavedMold>? decode(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (json is! List) return null;
    return [
      for (final e in json)
        if (_mold(e) case final SavedMold m) m,
    ];
  }

  static SavedMold? _mold(Object? e) {
    if (e is! Map) return null;
    final id = e['id'], name = e['name'], pts = e['pts'];
    if (id is! String || id.isEmpty || name is! String || pts is! List) {
      return null;
    }
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
    return SavedMold(
      id.length > 64 ? id.substring(0, 64) : id,
      name.length > maxNameLength ? name.substring(0, maxNameLength) : name,
      outline,
    );
  }

  static String encode(List<SavedMold> molds) => jsonEncode([
    for (final m in molds)
      {
        'id': m.id,
        'name': m.name,
        'pts': [
          for (final p in m.outline.points)
            [
              double.parse(p.x.toStringAsFixed(2)),
              double.parse(p.y.toStringAsFixed(2)),
            ],
        ],
      },
  ]);
}
