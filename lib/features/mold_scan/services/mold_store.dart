import 'dart:convert';

import 'package:web/web.dart' as web;

import 'mold_outline.dart';
import 'saved_mold_codec.dart';
import 'scan_history_codec.dart';

export 'saved_mold_codec.dart' show SavedMold;
export 'scan_history_codec.dart' show ScanRecord;

/// Saved molds live only in this browser on this device: clearing site data
/// or using another phone starts empty. Every access is guarded, since
/// storage can be blocked (private window).
class MoldStore {
  static const _key = 'mt_saved_molds_v1';
  static const _favKey = 'mt_fav_molds_v1';
  static const _priceKey = 'mt_prices_v1';
  // v2: distances measured from the outer edges of the black squares.
  static const _spanKey = 'mt_marker_spans_v2';
  static const _historyKey = 'mt_scan_history_v1';

  // Unreadable saved-mold data is copied here before anything overwrites it,
  // so a corrupted list can still be recovered by hand.
  static const _backupKey = 'mt_saved_molds_v1_unreadable';

  static List<SavedMold> load() {
    try {
      final raw = web.window.localStorage.getItem(_key);
      if (raw == null) return [];
      return SavedMoldCodec.decode(raw) ?? [];
    } catch (_) {
      return [];
    }
  }

  static bool _write(List<SavedMold> molds) {
    try {
      final storage = web.window.localStorage;
      final old = storage.getItem(_key);
      if (old != null && SavedMoldCodec.decode(old) == null) {
        storage.setItem(_backupKey, old);
      }
      storage.setItem(_key, SavedMoldCodec.encode(molds));
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

  /// Every finished scan, newest first (at most
  /// [ScanHistoryCodec.maxRecords]).
  static List<ScanRecord> history() {
    try {
      final raw = web.window.localStorage.getItem(_historyKey);
      if (raw == null) return [];
      return ScanHistoryCodec.decode(raw) ?? [];
    } catch (_) {
      return [];
    }
  }

  static bool _writeHistory(List<ScanRecord> records) {
    // The browser gives a few MB per site: when full, drop the oldest scans
    // until it fits.
    var list = records.take(ScanHistoryCodec.maxRecords).toList();
    while (list.isNotEmpty) {
      try {
        web.window.localStorage.setItem(
          _historyKey,
          ScanHistoryCodec.encode(list),
        );
        return true;
      } catch (_) {
        if (list.length == 1) return false;
        list = list.sublist(0, list.length - 1);
      }
    }
    try {
      web.window.localStorage.removeItem(_historyKey);
    } catch (_) {}
    return true;
  }

  /// Returns false when the browser refused to store it.
  static bool addToHistory(ScanRecord record) =>
      _writeHistory([record, ...history()]);

  static bool removeFromHistory(String id) =>
      _writeHistory(history().where((r) => r.id != id).toList());

  static bool clearHistory() => _writeHistory(const []);
}
