import 'dart:math' as math;
import 'package:pose/src/masked_array.dart';

/// Geometric pose representations, ported from the Python
/// `pose_format.*.representation` modules. Each operates on the trailing
/// (dimensions) axis of a [MaskedArray] shaped `(..., Dims)` and collapses it,
/// returning a zero-filled [MaskedArray] shaped `(...)`.

/// Euclidean distance between two sets of points.
class DistanceRepresentation {
  /// Distance along the last axis: `sqrt(sum((p1 - p2)^2))`, masked entries
  /// filled with zero.
  MaskedArray distance(MaskedArray p1s, MaskedArray p2s) {
    final MaskedArray diff = p1s.subtract(p2s);
    final MaskedArray squared = diff.multiply(diff);
    return squared.sum({diff.ndim - 1}).sqrt().filled(0);
  }

  MaskedArray call(MaskedArray p1s, MaskedArray p2s) => distance(p1s, p2s);
}

/// Angle (radians) between the X/Y axis and the segment `p1 -> p2`,
/// `atan(dy / dx)` (matching the Python implementation, which uses `atan`).
class AngleRepresentation {
  MaskedArray call(MaskedArray p1s, MaskedArray p2s) {
    final MaskedArray d = p2s.subtract(p1s);
    final MaskedArray xs = d.takeLast(0);
    final MaskedArray ys = d.takeLast(1);
    final MaskedArray slopes = ys.divide(xs).fixNaN().zeroFilled();
    return slopes.mapValues(math.atan);
  }
}

MaskedArray _normalizeVectors(MaskedArray v) {
  final MaskedArray magnitude = v.multiply(v).sum({v.ndim - 1}).sqrt();
  return v.divide(magnitude.unsqueezeLast());
}

/// Inner angle (radians) at `p2` in the triangle `(p1, p2, p3)`.
class InnerAngleRepresentation {
  MaskedArray call(MaskedArray p1s, MaskedArray p2s, MaskedArray p3s) {
    final MaskedArray v1 = _normalizeVectors(p1s.subtract(p2s));
    final MaskedArray v2 = _normalizeVectors(p3s.subtract(p2s));
    final MaskedArray cosines = v1.multiply(v2).sum({v1.ndim - 1});
    return cosines.mapValues(math.acos).zeroFilled().fixNaN();
  }
}

/// Distance from point `p1` to the line through `p2` and `p3`, via Heron's
/// formula.
class PointLineDistanceRepresentation {
  final DistanceRepresentation _distance = DistanceRepresentation();

  MaskedArray call(MaskedArray p1s, MaskedArray p2s, MaskedArray p3s) {
    final MaskedArray a = _distance.distance(p1s, p2s);
    final MaskedArray b = _distance.distance(p2s, p3s);
    final MaskedArray c = _distance.distance(p1s, p3s);
    final MaskedArray s = a.add(b).add(c).divide(2);
    final MaskedArray area = s
        .multiply(s.subtract(a))
        .multiply(s.subtract(b))
        .multiply(s.subtract(c))
        .sqrt();
    // height of the triangle relative to base b
    return area.multiply(2).divide(b).fixNaN().zeroFilled();
  }
}

/// Reshapes points `(Points, Batch, Len, Dims)` into `(Points*Dims, Batch, Len)`
/// (zero-filling masked values), matching the Python `PointsRepresentation`.
class PointsRepresentation {
  MaskedArray call(MaskedArray p1s) {
    final MaskedArray t = p1s.zeroFilled().permute([0, 3, 1, 2]);
    final List<int> s = t.shape;
    return t.reshape([s[0] * s[1], s[2], s[3]]);
  }
}
