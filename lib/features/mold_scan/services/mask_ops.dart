import 'dart:math';
import 'dart:typed_data';

/// Pixel-mask operations used to clean up the "is it the mold?" mask before
/// its outline is traced. A mask is a row-major 0/1 [Uint8List] of [w] x [h].

/// Zeroes the inclusive rectangle x0..x1, y0..y1 (clipped to the mask).
void clearRect(Uint8List mask, int w, int h, int x0, int x1, int y0, int y1) {
  if (x1 < 0 || y1 < 0 || x0 > w - 1 || y0 > h - 1) return;
  final xa = x0.clamp(0, w - 1), xb = x1.clamp(0, w - 1);
  final ya = y0.clamp(0, h - 1), yb = y1.clamp(0, h - 1);
  for (var y = ya; y <= yb; y++) {
    mask.fillRange(y * w + xa, y * w + xb + 1, 0);
  }
}

/// Square dilation (or erosion) of [src] with a (2r+1) window, done as two
/// 1-D passes using running sums. Pixels outside the image count as 0.
Uint8List boxMorph(Uint8List src, int w, int h, int r, {required bool erode}) {
  final window = 2 * r + 1;
  final tmp = Uint8List(w * h);
  final out = Uint8List(w * h);
  final prefix = Int32List(max(w, h) + 1);

  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      prefix[x + 1] = prefix[x] + src[row + x];
    }
    for (var x = 0; x < w; x++) {
      final sum = prefix[min(x + r, w - 1) + 1] - prefix[max(x - r, 0)];
      tmp[row + x] = erode ? (sum == window ? 1 : 0) : (sum > 0 ? 1 : 0);
    }
  }
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      prefix[y + 1] = prefix[y] + tmp[y * w + x];
    }
    for (var y = 0; y < h; y++) {
      final sum = prefix[min(y + r, h - 1) + 1] - prefix[max(y - r, 0)];
      out[y * w + x] = erode ? (sum == window ? 1 : 0) : (sum > 0 ? 1 : 0);
    }
  }
  return out;
}

/// Closes gaps up to 2r wide (dilate, then erode). Straight edges stay where
/// they are; a groove or joint splitting one piece in two gets filled.
Uint8List closeGaps(Uint8List mask, int w, int h, int r) =>
    boxMorph(boxMorph(mask, w, h, r, erode: false), w, h, r, erode: true);

/// Removes, in place, thin slivers (a table edge, a seam, a shadow line
/// touching the piece): keeps only pixels within [r] of the shape that
/// survives an opening. Reconstructing like this, instead of just opening,
/// keeps the sharp corners of the piece intact.
///
/// Within [edgeZone] pixels of the image border only 1 pixel is restored: a
/// thin strip of floor or table lying against the ignored border, touching a
/// piece that stands on it, would otherwise be restored for [r] pixels on each
/// side of the piece and widen it.
void dropSlivers(Uint8List mask, int w, int h, int r, {int edgeZone = 0}) {
  final opened = boxMorph(
    boxMorph(mask, w, h, r, erode: true),
    w,
    h,
    r,
    erode: false,
  );
  final near = boxMorph(opened, w, h, r, erode: false);
  final tight = edgeZone > 0 ? boxMorph(opened, w, h, 1, erode: false) : near;
  for (var y = 0; y < h; y++) {
    final edgeRow = y < edgeZone || y >= h - edgeZone;
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (mask[i] == 0) continue;
      final atEdge = edgeRow || x < edgeZone || x >= w - edgeZone;
      if ((atEdge ? tight : near)[i] == 0) mask[i] = 0;
    }
  }
}

/// Labels the 8-connected blobs of [mask] (labels start at 1) and reports the
/// biggest one. With no blob, `bestCount` is 0.
({Int32List labels, int bestLabel, int bestCount}) labelLargest(
  Uint8List mask,
  int w,
  int h,
) {
  final n = w * h;
  final labels = Int32List(n);
  final stack = Int32List(n);
  var nextLabel = 0, bestLabel = 0, bestCount = 0;
  for (var start = 0; start < n; start++) {
    if (mask[start] == 0 || labels[start] != 0) continue;
    nextLabel++;
    var sp = 0, count = 0;
    stack[sp++] = start;
    labels[start] = nextLabel;
    while (sp > 0) {
      final p = stack[--sp];
      count++;
      final x = p % w, y = p ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          final q = ny * w + nx;
          if (mask[q] != 0 && labels[q] == 0) {
            labels[q] = nextLabel;
            stack[sp++] = q;
          }
        }
      }
    }
    if (count > bestCount) {
      bestCount = count;
      bestLabel = nextLabel;
    }
  }
  return (labels: labels, bestLabel: bestLabel, bestCount: bestCount);
}

/// Fills background pixels that have foreground within [maxGap] px in all 4
/// directions (left, right, up and down). Stains and streaks inside a piece
/// that read as "board" leave holes and bites that this closes, while a real
/// concavity of the outline (the notch of a heart, the inside of an L or a
/// C) is open to at least one side and stays as it is.
Uint8List fillEnclosed(Uint8List mask, int w, int h, int maxGap) {
  final out = Uint8List.fromList(mask);
  final big = maxGap + 1;
  final left = Int32List(w * h), right = Int32List(w * h);
  final up = Int32List(w * h), down = Int32List(w * h);
  for (var y = 0; y < h; y++) {
    var d = big;
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      d = mask[i] != 0 ? 0 : (d >= big ? big : d + 1);
      left[i] = d;
    }
    d = big;
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      d = mask[i] != 0 ? 0 : (d >= big ? big : d + 1);
      right[i] = d;
    }
  }
  for (var x = 0; x < w; x++) {
    var d = big;
    for (var y = 0; y < h; y++) {
      final i = y * w + x;
      d = mask[i] != 0 ? 0 : (d >= big ? big : d + 1);
      up[i] = d;
    }
    d = big;
    for (var y = h - 1; y >= 0; y--) {
      final i = y * w + x;
      d = mask[i] != 0 ? 0 : (d >= big ? big : d + 1);
      down[i] = d;
    }
  }
  for (var i = 0; i < out.length; i++) {
    if (out[i] == 0 &&
        left[i] <= maxGap &&
        right[i] <= maxGap &&
        up[i] <= maxGap &&
        down[i] <= maxGap) {
      out[i] = 1;
    }
  }
  return out;
}

/// Marks as foreground every background pixel that the background around
/// the image cannot reach (4-connected flood fill from the border): the
/// holes of the shape. Run before [dropSlivers], whose opening would erase
/// the thin outer edge of a piece (a board's side face, a few mm wide) and
/// let a dark stain inside it leak out as a bite.
Uint8List fillHoles(Uint8List mask, int w, int h) {
  final reached = Uint8List(w * h);
  final stack = <int>[];
  void seed(int i) {
    if (mask[i] == 0 && reached[i] == 0) {
      reached[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w;
    if (x > 0) seed(i - 1);
    if (x < w - 1) seed(i + 1);
    if (i >= w) seed(i - w);
    if (i < (h - 1) * w) seed(i + w);
  }
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = (mask[i] != 0 || reached[i] == 0) ? 1 : 0;
  }
  return out;
}
