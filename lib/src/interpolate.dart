/// 1-D interpolation helpers used by [PoseBody.interpolate].
///
/// Pure Dart replacements for the subset of `scipy.interpolate.interp1d`
/// behaviour the Python `pose_format` library relies on (linear and cubic).
library;

/// Returns [n] evenly spaced values from [start] to [stop] (inclusive),
/// matching `numpy.linspace`.
List<double> linspace(double start, double stop, int n) {
  if (n <= 1) return [start];
  final double step = (stop - start) / (n - 1);
  return [for (int i = 0; i < n; i++) start + step * i];
}

/// Finds the index `i` such that `xs[i] <= x <= xs[i+1]` (clamped to the ends).
/// Assumes [xs] is sorted ascending with length >= 2.
int _bracket(List<double> xs, double x) {
  int lo = 0, hi = xs.length - 1;
  while (hi - lo > 1) {
    final int mid = (hi + lo) >> 1;
    if (xs[mid] > x) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return lo;
}

/// Piecewise-linear interpolation of `(xs, ys)` evaluated at [x].
double linearInterp(List<double> xs, List<double> ys, double x) {
  if (xs.length == 1) return ys[0];
  final int i = _bracket(xs, x);
  final double h = xs[i + 1] - xs[i];
  if (h == 0) return ys[i];
  final double t = (x - xs[i]) / h;
  return ys[i] + t * (ys[i + 1] - ys[i]);
}

/// Natural cubic spline (second derivative zero at both ends), the standard
/// tridiagonal construction. With only two points it degrades to linear.
class NaturalCubicSpline {
  final List<double> xs;
  final List<double> ys;
  late final List<double> _y2;

  NaturalCubicSpline(this.xs, this.ys) {
    final int n = xs.length;
    _y2 = List<double>.filled(n, 0);
    final List<double> u = List<double>.filled(n, 0);
    for (int i = 1; i < n - 1; i++) {
      final double sig = (xs[i] - xs[i - 1]) / (xs[i + 1] - xs[i - 1]);
      final double p = sig * _y2[i - 1] + 2;
      _y2[i] = (sig - 1) / p;
      double uu = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) -
          (ys[i] - ys[i - 1]) / (xs[i] - xs[i - 1]);
      u[i] = (6 * uu / (xs[i + 1] - xs[i - 1]) - sig * u[i - 1]) / p;
    }
    for (int k = n - 2; k >= 0; k--) {
      _y2[k] = _y2[k] * _y2[k + 1] + u[k];
    }
  }

  double eval(double x) {
    final int lo = _bracket(xs, x);
    final int hi = lo + 1;
    final double h = xs[hi] - xs[lo];
    if (h == 0) return ys[lo];
    final double a = (xs[hi] - x) / h;
    final double b = (x - xs[lo]) / h;
    return a * ys[lo] +
        b * ys[hi] +
        ((a * a * a - a) * _y2[lo] + (b * b * b - b) * _y2[hi]) * (h * h) / 6;
  }
}
