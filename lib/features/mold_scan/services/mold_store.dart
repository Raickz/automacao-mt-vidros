import 'dart:convert';

import 'package:web/web.dart' as web;

import 'homography.dart';
import 'mold_outline.dart';

/// A mold the worker saved ("MEUS"), kept in this browser's localStorage.
class SavedMold {
  final String id;
  final String name;
  final MoldOutline outline;

  const SavedMold(this.id, this.name, this.outline);
}

/// Saved molds live only in this browser on this device: clearing site data
/// or using another phone starts empty. Every access is guarded, since
/// storage can be blocked (private window).
class MoldStore {
  static const _key = 'mt_saved_molds_v1';
  static const _favKey = 'mt_fav_molds_v1';
  static const _priceKey = 'mt_prices_v1';
  static const _spanKey = 'mt_marker_spans_v1';

  static List<SavedMold> load() {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          SavedMold(
            e['id'] as String,
            e['name'] as String,
            MoldOutline([
              for (final p in e['pts'] as List)
                Point2D((p[0] as num).toDouble(), (p[1] as num).toDouble()),
            ]),
          ),
      ];
    } catch (_) {
      return [];
    }
  }

  static bool _write(List<SavedMold> molds) {
    try {
      web.window.localStorage.setItem(
        _key,
        jsonEncode([
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
        ]),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns false when the browser refused to store it.
  static bool add(String name, MoldOutline outline) {
    final all = load();
    all.insert(
      0,
      SavedMold(
        DateTime.now().microsecondsSinceEpoch.toString(),
        name,
        outline.normalized(),
      ),
    );
    return _write(all);
  }

  static bool remove(String id) =>
      _write(load().where((m) => m.id != id).toList());

  static Set<String> favorites() {
    try {
      final raw = web.window.localStorage.getItem(_favKey);
      return raw == null ? {} : {...(jsonDecode(raw) as List).cast<String>()};
    } catch (_) {
      return {};
    }
  }

  static void setFavorites(Set<String> codes) {
    try {
      web.window.localStorage.setItem(_favKey, jsonEncode(codes.toList()));
    } catch (_) {}
  }

  /// Last typed prices (R$/m² of glass, R$/m of edge), as typed.
  static (String, String) prices() {
    try {
      final raw = web.window.localStorage.getItem(_priceKey);
      if (raw == null) return ('', '');
      final m = jsonDecode(raw) as Map;
      return ((m['m2'] ?? '') as String, (m['m'] ?? '') as String);
    } catch (_) {
      return ('', '');
    }
  }

  static void setPrices(String perM2, String perMeter) {
    try {
      web.window.localStorage.setItem(
        _priceKey,
        jsonEncode({'m2': perM2, 'm': perMeter}),
      );
    } catch (_) {}
  }

  /// Marker spacing typed in "Escala" (cm, as typed): markers glued on a
  /// wall stay put, so it is measured once and remembered.
  static (String, String) markerSpans() {
    try {
      final raw = web.window.localStorage.getItem(_spanKey);
      if (raw == null) return ('', '');
      final m = jsonDecode(raw) as Map;
      return ((m['x'] ?? '') as String, (m['y'] ?? '') as String);
    } catch (_) {
      return ('', '');
    }
  }

  static void setMarkerSpans(String x, String y) {
    try {
      web.window.localStorage.setItem(_spanKey, jsonEncode({'x': x, 'y': y}));
    } catch (_) {}
  }
}
