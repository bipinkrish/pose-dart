import 'dart:math' as math;
import 'dart:typed_data';

/// A masked, N-dimensional array of doubles stored row-major in a flat buffer.
///
/// This is the Dart analogue of NumPy's `numpy.ma.MaskedArray` used throughout
/// the Python `pose_format` library. A value is "masked" (invalid / missing)
/// when its [mask] entry is non-zero. Reductions ([mean], [std], [min], [max],
/// [sum]) ignore masked entries; element-wise operations apply to the
/// underlying values regardless of mask and propagate the mask.
class MaskedArray {
  /// Flat, row-major values.
  final Float64List values;

  /// Flat mask aligned with [values]: 1 = masked (invalid), 0 = valid.
  final Uint8List mask;

  /// Dimensions of the array.
  final List<int> shape;

  /// Row-major strides derived from [shape].
  final List<int> strides;

  MaskedArray(this.values, this.mask, List<int> shape)
      : shape = List<int>.unmodifiable(shape),
        strides = _strides(shape) {
    assert(values.length == mask.length);
    assert(values.length == _prod(shape));
  }

  int get ndim => shape.length;
  int get size => values.length;

  static int _prod(List<int> s) => s.fold(1, (a, b) => a * b);

  static List<int> _strides(List<int> shape) {
    final List<int> s = List<int>.filled(shape.length, 1);
    for (int i = shape.length - 2; i >= 0; i--) {
      s[i] = s[i + 1] * shape[i + 1];
    }
    return s;
  }

  // ---------------------------------------------------------------------------
  // Construction
  // ---------------------------------------------------------------------------

  /// Builds a MaskedArray from pose [data] (nested `[frames][people][points][dims]`)
  /// and [confidence] (`[frames][people][points]`). A point is masked when its
  /// confidence is zero, applied across all of its dimensions.
  factory MaskedArray.fromPose(List data, List confidence) {
    final List<int> shape = _nestedShape(data);
    if (shape.length != 4) {
      throw ArgumentError('Pose data must be 4-dimensional, got shape $shape');
    }
    final Float64List values = Float64List(_prod(shape));
    final Uint8List mask = Uint8List(values.length);
    final int dims = shape[3];

    int vi = 0;
    for (int f = 0; f < shape[0]; f++) {
      for (int p = 0; p < shape[1]; p++) {
        for (int n = 0; n < shape[2]; n++) {
          final bool masked = (confidence[f][p][n] as num) == 0;
          for (int d = 0; d < dims; d++) {
            values[vi] = (data[f][p][n][d] as num).toDouble();
            if (masked) mask[vi] = 1;
            vi++;
          }
        }
      }
    }
    return MaskedArray(values, mask, shape);
  }

  /// Builds an unmasked MaskedArray from arbitrarily-nested numeric lists.
  factory MaskedArray.fromNested(dynamic nested) {
    final List<int> shape = _nestedShape(nested);
    final Float64List values = Float64List(_prod(shape));
    int i = 0;
    void fill(dynamic x) {
      if (x is num) {
        values[i++] = x.toDouble();
      } else {
        for (final dynamic e in x as List) {
          fill(e);
        }
      }
    }

    fill(nested);
    return MaskedArray(values, Uint8List(values.length), shape);
  }

  static List<int> _nestedShape(dynamic nested) {
    final List<int> shape = [];
    dynamic cur = nested;
    while (cur is List) {
      shape.add(cur.length);
      cur = cur.isEmpty ? null : cur[0];
    }
    return shape;
  }

  // ---------------------------------------------------------------------------
  // Conversion
  // ---------------------------------------------------------------------------

  /// Converts to nested lists. Masked positions keep their underlying value
  /// unless [fill] is provided, in which case masked entries are replaced.
  dynamic toNested({double? fill}) {
    int offset = 0;
    dynamic build(int dim) {
      if (dim == shape.length) {
        final double v = values[offset];
        final bool m = mask[offset] != 0;
        offset++;
        return (fill != null && m) ? fill : v;
      }
      return List.generate(shape[dim], (_) => build(dim + 1));
    }

    if (shape.isEmpty) {
      return (fill != null && mask[0] != 0) ? fill : values[0];
    }
    return build(0);
  }

  /// The single value of a scalar (size-1) array.
  double get scalar {
    if (size != 1) {
      throw StateError('scalar getter requires size 1, got shape $shape');
    }
    return values[0];
  }

  MaskedArray copy() => MaskedArray(
      Float64List.fromList(values), Uint8List.fromList(mask), shape.toList());

  // ---------------------------------------------------------------------------
  // Element-wise operations
  // ---------------------------------------------------------------------------

  /// Applies [f] to every value, preserving the mask.
  MaskedArray mapValues(double Function(double) f) {
    final Float64List out = Float64List(size);
    for (int i = 0; i < size; i++) {
      out[i] = f(values[i]);
    }
    return MaskedArray(out, Uint8List.fromList(mask), shape.toList());
  }

  MaskedArray sqrt() => mapValues(math.sqrt);

  MaskedArray add(dynamic other) => _binary(other, (a, b) => a + b);
  MaskedArray subtract(dynamic other) => _binary(other, (a, b) => a - b);
  MaskedArray multiply(dynamic other) => _binary(other, (a, b) => a * b);
  MaskedArray divide(dynamic other) => _binary(other, (a, b) => a / b);

  MaskedArray _binary(dynamic other, double Function(double, double) op) {
    if (other is num) {
      final double b = other.toDouble();
      final Float64List out = Float64List(size);
      for (int i = 0; i < size; i++) {
        out[i] = op(values[i], b);
      }
      return MaskedArray(out, Uint8List.fromList(mask), shape.toList());
    }
    if (other is MaskedArray) {
      return _broadcastBinary(this, other, op);
    }
    throw ArgumentError('Operand must be num or MaskedArray, got $other');
  }

  static MaskedArray _broadcastBinary(
      MaskedArray a, MaskedArray b, double Function(double, double) op) {
    final int rank = math.max(a.ndim, b.ndim);
    final List<int> outShape = List<int>.filled(rank, 1);
    final List<int> aStride = List<int>.filled(rank, 0);
    final List<int> bStride = List<int>.filled(rank, 0);

    for (int i = 0; i < rank; i++) {
      final int ai = a.ndim - rank + i; // aligned-from-trailing index into a
      final int bi = b.ndim - rank + i;
      final int as_ = ai >= 0 ? a.shape[ai] : 1;
      final int bs = bi >= 0 ? b.shape[bi] : 1;
      if (as_ != bs && as_ != 1 && bs != 1) {
        throw ArgumentError(
            'Cannot broadcast shapes ${a.shape} and ${b.shape}');
      }
      outShape[i] = math.max(as_, bs);
      aStride[i] = (ai >= 0 && as_ != 1) ? a.strides[ai] : 0;
      bStride[i] = (bi >= 0 && bs != 1) ? b.strides[bi] : 0;
    }

    final int total = _prod(outShape);
    final Float64List out = Float64List(total);
    final Uint8List outMask = Uint8List(total);
    final List<int> idx = List<int>.filled(rank, 0);

    for (int flat = 0; flat < total; flat++) {
      int ai = 0, bi = 0;
      for (int d = 0; d < rank; d++) {
        ai += idx[d] * aStride[d];
        bi += idx[d] * bStride[d];
      }
      out[flat] = op(a.values[ai], b.values[bi]);
      if (a.mask[ai] != 0 || b.mask[bi] != 0) outMask[flat] = 1;

      // increment multi-index (row-major)
      for (int d = rank - 1; d >= 0; d--) {
        if (++idx[d] < outShape[d]) break;
        idx[d] = 0;
      }
    }
    return MaskedArray(out, outMask, outShape);
  }

  // ---------------------------------------------------------------------------
  // Reductions (mask-aware, ddof=0 to match numpy.ma defaults)
  // ---------------------------------------------------------------------------

  /// Collects valid values into one bucket per output cell after removing
  /// [axes]. Returns the buckets and the resulting (reduced) shape.
  (List<List<double>>, List<int>) _collect(Set<int> axes) {
    final List<int> keepAxes = [
      for (int i = 0; i < ndim; i++)
        if (!axes.contains(i)) i
    ];
    final List<int> outShape = [for (final int a in keepAxes) shape[a]];
    final List<int> outStrides = _strides(outShape);
    final int outSize = _prod(outShape);
    final List<List<double>> buckets =
        List.generate(outSize, (_) => <double>[]);

    final List<int> idx = List<int>.filled(ndim, 0);
    for (int flat = 0; flat < size; flat++) {
      if (mask[flat] == 0) {
        int outFlat = 0;
        for (int k = 0; k < keepAxes.length; k++) {
          outFlat += idx[keepAxes[k]] * outStrides[k];
        }
        buckets[outFlat].add(values[flat]);
      }
      for (int d = ndim - 1; d >= 0; d--) {
        if (++idx[d] < shape[d]) break;
        idx[d] = 0;
      }
    }
    return (buckets, outShape);
  }

  MaskedArray _reduce(Set<int> axes, double Function(List<double>) agg) {
    final (buckets, outShape) = _collect(axes);
    final Float64List out = Float64List(buckets.length);
    final Uint8List outMask = Uint8List(buckets.length);
    for (int i = 0; i < buckets.length; i++) {
      if (buckets[i].isEmpty) {
        outMask[i] = 1;
      } else {
        out[i] = agg(buckets[i]);
      }
    }
    return MaskedArray(out, outMask, outShape);
  }

  /// Mean over [axes] (defaults to all axes), ignoring masked entries.
  MaskedArray mean([Set<int>? axes]) => _reduce(
      axes ?? {for (int i = 0; i < ndim; i++) i},
      (v) => v.reduce((a, b) => a + b) / v.length);

  /// Population standard deviation (ddof=0) over [axes], ignoring masked.
  MaskedArray std([Set<int>? axes]) =>
      _reduce(axes ?? {for (int i = 0; i < ndim; i++) i}, (v) {
        final double m = v.reduce((a, b) => a + b) / v.length;
        double s = 0;
        for (final double x in v) {
          s += (x - m) * (x - m);
        }
        return math.sqrt(s / v.length);
      });

  /// Sum over [axes], ignoring masked entries.
  MaskedArray sum([Set<int>? axes]) => _reduce(
      axes ?? {for (int i = 0; i < ndim; i++) i},
      (v) => v.reduce((a, b) => a + b));

  /// Minimum over [axes], ignoring masked entries.
  MaskedArray min([Set<int>? axes]) => _reduce(
      axes ?? {for (int i = 0; i < ndim; i++) i}, (v) => v.reduce(math.min));

  /// Maximum over [axes], ignoring masked entries.
  MaskedArray max([Set<int>? axes]) => _reduce(
      axes ?? {for (int i = 0; i < ndim; i++) i}, (v) => v.reduce(math.max));

  // ---------------------------------------------------------------------------
  // Shape operations
  // ---------------------------------------------------------------------------

  /// Returns a new array with axes permuted per [axes] (a permutation of
  /// `0..ndim-1`), like `numpy.transpose`.
  MaskedArray permute(List<int> axes) {
    if (axes.length != ndim) {
      throw ArgumentError('permute expects $ndim axes, got ${axes.length}');
    }
    final List<int> outShape = [for (final int a in axes) shape[a]];
    final List<int> outStrides = _strides(outShape);
    final Float64List out = Float64List(size);
    final Uint8List outMask = Uint8List(size);

    final List<int> idx = List<int>.filled(ndim, 0); // index into source
    for (int flat = 0; flat < size; flat++) {
      int outFlat = 0;
      for (int k = 0; k < axes.length; k++) {
        outFlat += idx[axes[k]] * outStrides[k];
      }
      out[outFlat] = values[flat];
      outMask[outFlat] = mask[flat];
      for (int d = ndim - 1; d >= 0; d--) {
        if (++idx[d] < shape[d]) break;
        idx[d] = 0;
      }
    }
    return MaskedArray(out, outMask, outShape);
  }

  /// Indexes the first axis with a single integer, reducing rank by one
  /// (e.g. `arr[i]`).
  MaskedArray takeFirst(int i) {
    final int block = strides[0];
    final int start = i * block;
    return MaskedArray(Float64List.sublistView(values, start, start + block),
        Uint8List.sublistView(mask, start, start + block), shape.sublist(1));
  }

  /// Gathers slices along the first axis (fancy indexing, e.g. `arr[indexes]`).
  MaskedArray gatherFirst(List<int> indexes) {
    final int block = strides[0];
    final Float64List out = Float64List(indexes.length * block);
    final Uint8List outMask = Uint8List(out.length);
    for (int k = 0; k < indexes.length; k++) {
      final int src = indexes[k] * block;
      out.setRange(k * block, (k + 1) * block, values, src);
      outMask.setRange(k * block, (k + 1) * block, mask, src);
    }
    return MaskedArray(out, outMask, [indexes.length, ...shape.sublist(1)]);
  }

  // ---------------------------------------------------------------------------
  // Matrix multiplication
  // ---------------------------------------------------------------------------

  /// Multiplies the last axis by [matrix] (`[D][D2]`), like `numpy.dot` over the
  /// trailing dimension: `(..., D) · (D, D2) -> (..., D2)`. Masked inputs are
  /// treated as zero and the mask is carried to the output.
  MaskedArray matmul(List<List<double>> matrix) {
    final int d = shape.last;
    if (matrix.length != d) {
      throw ArgumentError('matrix rows (${matrix.length}) must equal last '
          'dimension ($d)');
    }
    final int d2 = matrix[0].length;
    final int rows = size ~/ d;
    final List<int> outShape = [...shape.sublist(0, ndim - 1), d2];
    final Float64List out = Float64List(rows * d2);
    final Uint8List outMask = Uint8List(out.length);

    for (int r = 0; r < rows; r++) {
      final int inBase = r * d;
      final int outBase = r * d2;
      for (int j = 0; j < d2; j++) {
        double acc = 0;
        bool anyMasked = false;
        for (int k = 0; k < d; k++) {
          final int fi = inBase + k;
          if (mask[fi] != 0) {
            anyMasked = true;
          } else {
            acc += values[fi] * matrix[k][j];
          }
        }
        out[outBase + j] = acc;
        if (anyMasked) outMask[outBase + j] = 1;
      }
    }
    return MaskedArray(out, outMask, outShape);
  }
}
