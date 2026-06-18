// ignore_for_file: non_constant_identifier_names, no_leading_underscores_for_local_identifiers, prefer_typing_uninitialized_variables

import 'dart:math';
import 'package:pose/src/pose_header.dart';
import 'package:pose/src/masked_array.dart';
import 'package:pose/src/interpolate.dart';
import 'package:pose/reader.dart';
import 'package:pose/writer.dart';
import 'package:pose/numdart.dart';

/// Permutation applied by [PoseBody.pointsPerspective]: (frames, people,
/// points, dims) -> (points, people, frames, dims).
const List<int> pointsDims = [2, 1, 0, 3];

/// Class representing a pose body.
///
/// This class provides functionality to read pose body data.
class PoseBody {
  final double fps;

  /// Pose data, nested as `[frames][people][points][dims]`. Mutable so that
  /// in-place transforms (e.g. [Pose.normalize], [Pose.focus]) can replace it.
  dynamic data;

  /// Per-point confidence, nested as `[frames][people][points]`.
  List<dynamic> confidence;

  /// Constructor for PoseBody.
  ///
  /// Takes [fps], [data], and [confidence] as parameters.
  PoseBody(this.fps, this.data, this.confidence);

  /// Number of frames.
  int get length => (data as List).length;

  /// Builds a [MaskedArray] from [data] and [confidence] (points with zero
  /// confidence are masked across all dimensions).
  MaskedArray get maskedData => MaskedArray.fromPose(data as List, confidence);

  /// Transposes the data to `(points, people, frames, dims)`.
  MaskedArray pointsPerspective() => maskedData.permute(pointsDims);

  /// Returns a new body with the last dimension multiplied by [matrix]
  /// (`[dims][dims2]`).
  PoseBody matmul(List<List<double>> matrix) =>
      PoseBody(fps, maskedData.matmul(matrix).toNested(), confidence);

  /// Augments 2D points with random rotation, shear and scaling (radians /
  /// fractions). Pass [rng] for deterministic output.
  PoseBody augment2d(
      {double rotationStd = 0.2,
      double shearStd = 0.2,
      double scaleStd = 0.2,
      Random? rng}) {
    final Random r = rng ?? Random();
    List<List<double>> matrix = _eye(2);

    if (shearStd > 0) {
      final List<List<double>> shear = _eye(2);
      shear[0][1] = _gaussian(r, 0, shearStd);
      matrix = _matmul2(matrix, shear);
    }
    if (rotationStd > 0) {
      final double angle = _gaussian(r, 0, rotationStd);
      final double c = cos(angle), s = sin(angle);
      matrix = _matmul2(matrix, [
        [c, -s],
        [s, c]
      ]);
    }
    if (scaleStd > 0) {
      final List<List<double>> scale = _eye(2);
      scale[1][1] += _gaussian(r, 0, scaleStd);
      matrix = _matmul2(matrix, scale);
    }

    final int dims = (data[0][0][0] as List).length;
    final List<List<double>> dimMatrix = _eye(dims);
    for (int i = 0; i < 2; i++) {
      for (int j = 0; j < 2; j++) {
        dimMatrix[i][j] = matrix[i][j];
      }
    }
    return this.matmul(dimMatrix);
  }

  /// Flips the data across [axis] (negates that dimension).
  PoseBody flip({int axis = 0}) {
    final int dims = (data[0][0][0] as List).length;
    final List<num> vec = List<num>.filled(dims, 1);
    vec[axis] = -1;
    return PoseBody(
        fps,
        maskedData.multiply(MaskedArray.fromNested(vec)).toNested(),
        confidence);
  }

  /// Returns a copy with masked (missing) values replaced by zero.
  PoseBody zeroFilled() =>
      PoseBody(fps, maskedData.toNested(fill: 0), confidence);

  /// Deep copy of this body.
  PoseBody copy() => PoseBody(fps, _deepCopy(data), _deepCopy(confidence));

  /// Keeps only the points at the given flat [indexes] (in all frames/people).
  PoseBody getPoints(List<int> indexes) {
    final MaskedArray persp = maskedData.permute(pointsDims);
    final dynamic newData =
        persp.gatherFirst(indexes).permute(pointsDims).toNested();

    final List newConfidence = [
      for (final dynamic frame in confidence)
        [
          for (final dynamic person in frame as List)
            [for (final int i in indexes) (person as List)[i]]
        ]
    ];
    return PoseBody(fps, newData, newConfidence);
  }

  /// Keeps only the given [frameIndexes].
  PoseBody selectFrames(List<int> frameIndexes) {
    final List d = data as List;
    final List c = confidence;
    return PoseBody(fps, [for (final int i in frameIndexes) d[i]],
        [for (final int i in frameIndexes) c[i]]);
  }

  /// Keeps every [by]-th frame, scaling [fps] accordingly.
  PoseBody sliceStep(int by) {
    final List d = data as List;
    final List c = confidence;
    final List<int> idx = [for (int i = 0; i < d.length; i += by) i];
    return PoseBody(fps / by, [for (final int i in idx) d[i]],
        [for (final int i in idx) c[i]]);
  }

  /// Drops a fixed [dropoutPercent] (0..1) of frames, returning the new body
  /// and the retained frame indices. Pass [rng] for deterministic output.
  (PoseBody, List<int>) frameDropoutGivenPercent(double dropoutPercent,
      {Random? rng}) {
    final Random r = rng ?? Random();
    final int dataLen = length;
    final int dropoutNumber =
        min((dataLen * dropoutPercent).toInt(), (dataLen * 0.99).toInt());

    final List<int> all = [for (int i = 0; i < dataLen; i++) i]..shuffle(r);
    final Set<int> dropped = all.take(dropoutNumber).toSet();
    final List<int> selected = [
      for (int i = 0; i < dataLen; i++)
        if (!dropped.contains(i)) i
    ];
    return (selectFrames(selected), selected);
  }

  /// Drops a uniform-random fraction of frames in `[dropoutMin, dropoutMax]`.
  (PoseBody, List<int>) frameDropoutUniform(
      {double dropoutMin = 0.2, double dropoutMax = 1.0, Random? rng}) {
    final Random r = rng ?? Random();
    final double pct = dropoutMin + r.nextDouble() * (dropoutMax - dropoutMin);
    return frameDropoutGivenPercent(pct, rng: r);
  }

  /// Drops a normal-random fraction of frames (mean/std), clamped to be
  /// non-negative.
  (PoseBody, List<int>) frameDropoutNormal(
      {double dropoutMean = 0.5, double dropoutStd = 0.1, Random? rng}) {
    final Random r = rng ?? Random();
    final double pct = _gaussian(r, dropoutMean, dropoutStd).abs();
    return frameDropoutGivenPercent(pct, rng: r);
  }

  /// Keeps the frame range `[start, end)` (defaults to the end of the data).
  PoseBody slice(int start, [int? end]) {
    final List d = data as List;
    final int stop = end ?? d.length;
    return selectFrames([for (int i = start; i < stop; i++) i]);
  }

  /// Number of frames between [startTime] and [endTime] (milliseconds,
  /// inclusive of both ends), defaulting to the whole clip.
  int durationInFrames({int? startTime, int? endTime}) {
    int startFrame = 0;
    if (startTime != null) {
      startFrame = (startTime / 1000 * fps).toInt();
      if (startFrame < 0 || startFrame >= length) {
        throw ArgumentError('Start frame $startFrame out of range');
      }
    }
    int endFrame = length - 1;
    if (endTime != null) {
      endFrame = (endTime / 1000 * fps).toInt();
      if (endFrame < 0 || endFrame >= length || startFrame > endFrame) {
        throw ArgumentError('End frame $endFrame out of range');
      }
    }
    return endFrame - startFrame + 1;
  }

  /// Resamples the pose to [newFps] (defaults to the current fps), filling
  /// missing points by interpolation.
  ///
  /// [kind] is `'linear'` or `'cubic'` (a natural cubic spline; `'quadratic'`
  /// is treated as cubic). Per point, only confident frames are used and
  /// timestamps outside a point's observed range are zero-filled — matching the
  /// Python implementation's behaviour (which uses scipy under the hood).
  PoseBody interpolate({double? newFps, String kind = 'cubic'}) {
    final double targetFps = newFps ?? fps;
    final List dataL = data as List;
    final int frames = dataL.length;
    if (frames == 1) {
      throw ArgumentError("Can't interpolate single frame");
    }
    final int people = (dataL[0] as List).length;
    final int points = (dataL[0][0] as List).length;
    final int dims = (dataL[0][0][0] as List).length;
    final int newFrames = (frames * targetFps / fps).round();

    final List<double> steps = linspace(0, 1, frames);
    final List<double> newSteps = linspace(0, 1, newFrames);

    final List newData = List.generate(
        newFrames,
        (_) => List.generate(people,
            (_) => List.generate(points, (_) => List<double>.filled(dims, 0))));
    final List newConfidence = List.generate(newFrames,
        (_) => List.generate(people, (_) => List<double>.filled(points, 0)));

    for (int p = 0; p < people; p++) {
      for (int n = 0; n < points; n++) {
        final List<double> validSteps = [];
        final List<List<double>> validRows =
            []; // each: dims values + confidence
        for (int f = 0; f < frames; f++) {
          final double conf = (confidence[f][p][n] as num).toDouble();
          if (conf > 0) {
            validSteps.add(steps[f]);
            validRows.add([
              for (int d = 0; d < dims; d++)
                (dataL[f][p][n][d] as num).toDouble(),
              conf
            ]);
          }
        }
        if (validSteps.isEmpty) continue; // leave zeros

        final double first = validSteps.first;
        final double last = validSteps.last;
        final int cols = dims + 1;
        final bool useCubic = kind != 'linear' && validSteps.length >= 3;

        final List<double Function(double)> interps = [
          for (int c = 0; c < cols; c++)
            _columnInterpolator(
                validSteps, [for (final r in validRows) r[c]], useCubic)
        ];

        for (int s = 0; s < newFrames; s++) {
          final double t = newSteps[s];
          if (t < first || t > last) continue; // zero-fill outside range
          for (int d = 0; d < dims; d++) {
            newData[s][p][n][d] = interps[d](t);
          }
          newConfidence[s][p][n] = interps[dims](t);
        }
      }
    }

    return PoseBody(targetFps, newData, newConfidence);
  }

  /// Computes per-component bounding boxes, producing two points per component
  /// (`TOP_LEFT` = min, `BOTTOM_RIGHT` = max) over the confident points.
  ///
  /// Pair with [PoseHeader.bbox] to build the matching header.
  PoseBody bbox(PoseHeader header) {
    final List dataL = data as List;
    final int frames = dataL.length;
    final int people = frames > 0 ? (dataL[0] as List).length : 0;
    final int dims = frames > 0 ? (dataL[0][0][0] as List).length : 0;
    final int numComps = header.components.length;
    final int newPoints = numComps * 2;

    final List newData = List.generate(
        frames,
        (_) => List.generate(
            people,
            (_) =>
                List.generate(newPoints, (_) => List<double>.filled(dims, 0))));
    final List newConfidence = List.generate(frames,
        (_) => List.generate(people, (_) => List<double>.filled(newPoints, 0)));

    for (int f = 0; f < frames; f++) {
      for (int p = 0; p < people; p++) {
        int idx = 0;
        for (int ci = 0; ci < numComps; ci++) {
          final int count = header.components[ci].points.length;
          bool any = false;
          final List<double> mins = List<double>.filled(dims, 0);
          final List<double> maxs = List<double>.filled(dims, 0);
          for (int n = idx; n < idx + count; n++) {
            if ((confidence[f][p][n] as num) > 0) {
              for (int d = 0; d < dims; d++) {
                final double v = (dataL[f][p][n][d] as num).toDouble();
                if (!any) {
                  mins[d] = v;
                  maxs[d] = v;
                } else {
                  if (v < mins[d]) mins[d] = v;
                  if (v > maxs[d]) maxs[d] = v;
                }
              }
              any = true;
            }
          }
          if (any) {
            newData[f][p][ci * 2] = mins;
            newData[f][p][ci * 2 + 1] = maxs;
            newConfidence[f][p][ci * 2] = 1.0;
            newConfidence[f][p][ci * 2 + 1] = 1.0;
          }
          idx += count;
        }
      }
    }
    return PoseBody(fps, newData, newConfidence);
  }

  /// Flattens confident points into rows of
  /// `[timeSeconds, personId, pointId, confidence, ...dims]`, dropping points
  /// with zero confidence.
  List<List<double>> flatten() {
    final List dataL = data as List;
    final int frames = dataL.length;
    final int people = frames > 0 ? (dataL[0] as List).length : 0;
    final int points = frames > 0 ? (dataL[0][0] as List).length : 0;
    final int dims = frames > 0 ? (dataL[0][0][0] as List).length : 0;

    final List<List<double>> out = [];
    for (int f = 0; f < frames; f++) {
      for (int p = 0; p < people; p++) {
        for (int n = 0; n < points; n++) {
          final double conf = (confidence[f][p][n] as num).toDouble();
          if (conf != 0) {
            out.add([
              f / fps,
              p.toDouble(),
              n.toDouble(),
              conf,
              for (int d = 0; d < dims; d++)
                (dataL[f][p][n][d] as num).toDouble(),
            ]);
          }
        }
      }
    }
    return out;
  }

  @override
  String toString() {
    final List dataL = data as List;
    final int frames = dataL.length;
    final int people = frames > 0 ? (dataL[0] as List).length : 0;
    final int points = frames > 0 ? (dataL[0][0] as List).length : 0;
    final int dims = frames > 0 ? (dataL[0][0][0] as List).length : 0;
    return 'PoseBody(fps: $fps, shape: [$frames, $people, $points, $dims], '
        'duration: ${frames / fps}s)';
  }

  /// Reads pose body data based on the provided header and reader.
  ///
  /// Returns a PoseBody instance.
  static PoseBody read(
      PoseHeader header, BufferReader reader, Map<String, dynamic> kwargs) {
    final int version_hundred = (header.version * 1000).round();
    if (version_hundred == 0) {
      return read_v0_0(header, reader, kwargs);
    }
    if (version_hundred == 100 || version_hundred == 200) {
      return read_v0_1(header, reader, version_hundred, kwargs);
    }

    throw UnimplementedError("Unknown version - ${header.version}");
  }

  /// Reads pose body data for version 0.0.
  ///
  /// In v0.0 each frame stores a variable number of people, and each point's
  /// coordinates and confidence are interleaved (the last value of every
  /// point's format is its confidence). Only the first person is kept, mirroring
  /// the Python implementation.
  static PoseBody read_v0_0(
      PoseHeader header, BufferReader reader, Map<String, dynamic> kwargs) {
    final List<dynamic> fpsFrames = reader.unpack(ConstStructs.double_ushort);
    final int fps = fpsFrames[0];
    final int frames = fpsFrames[1];

    final int dims = header.numDims();
    final int points = header.totalPoints();

    final List framesData = [];
    final List framesConfidence = [];

    for (int f = 0; f < frames; f++) {
      final int people = reader.unpack(ConstStructs.ushort);
      List? person0Data;
      List? person0Confidence;

      for (int pid = 0; pid < people; pid++) {
        reader.advance(ConstStructs.short); // Skip person ID
        final List personData = [];
        final List personConfidence = [];

        for (final PoseHeaderComponent component in header.components) {
          final int fmtLen = component.format.length;
          final List pts = reader
              .unpackNum(ConstStructs.float, [component.points.length, fmtLen]);
          for (final dynamic pt in pts) {
            personData.add((pt as List).sublist(0, fmtLen - 1));
            personConfidence.add(pt[fmtLen - 1]);
          }
        }

        if (pid == 0) {
          person0Data = personData;
          person0Confidence = personConfidence;
        }
      }

      // In case there is no person, fill with zeros.
      person0Data ??= List.generate(points, (_) => List.filled(dims, 0.0));
      person0Confidence ??= List.filled(points, 0.0);

      framesData.add([person0Data]);
      framesConfidence.add([person0Confidence]);
    }

    return PoseBody(fps.toDouble(), framesData, framesConfidence);
  }

  /// Reads pose body data for version 0.1 and 0.2.
  ///
  /// Takes [header], [reader], [version], and [kwargs] as parameters.
  /// Returns the read data.
  static dynamic read_v0_1(PoseHeader header, BufferReader reader, int version,
      Map<String, dynamic> kwargs) {
    late int fps, _frames;
    if (version == 100) {
      final List<dynamic> lst = reader.unpack(ConstStructs.double_ushort);
      fps = lst[0];
      _frames = lst[1];
    } else {
      // version == 200
      fps = reader.unpack(ConstStructs.float).toInt();
      _frames = reader.unpack(ConstStructs.float).toInt();
    }
    final int _people = reader.unpack(ConstStructs.ushort);

    final int _points =
        header.components.map((c) => c.points.length).reduce((a, b) => a + b);
    final int _dims = header.components
            .map((c) => c.format.length)
            .reduce((a, b) => a > b ? a : b) -
        1;
    _frames = reader.bytesLeft() ~/ (_people * _points * (_dims + 1) * 4);

    // Resolve frame slicing, allowing start/end to be given either as frame
    // indices or as times in milliseconds.
    int? startFrame = kwargs['startFrame'] as int?;
    int? endFrame = kwargs['endFrame'] as int?;
    final num? startTime = kwargs['startTime'] as num?;
    final num? endTime = kwargs['endTime'] as num?;
    if (startTime != null) {
      startFrame = (startTime / 1000 * fps).floor();
    }
    if (endTime != null) {
      endFrame = (endTime / 1000 * fps).ceil();
    }

    final List data = read_v0_1_frames(
        _frames, [_people, _points, _dims], reader, startFrame, endFrame);
    final List confidence = read_v0_1_frames(
        _frames, [_people, _points], reader, startFrame, endFrame);

    return PoseBody(fps.toDouble(), data, confidence);
  }

  /// Writes this pose body to the [writer] using the v0.2 format
  /// (float fps, uint frame count, ushort people count, then float32 data and
  /// float32 confidence). Mirrors the Python implementation, which always
  /// emits the latest format.
  void write(BufferWriter writer) {
    final int frames = data.length;
    final int people = frames > 0 ? (data[0] as List).length : 0;

    writer.packFloat(fps);
    writer.packUInt(frames);
    writer.packUShort(people);
    writer.packFloats(data);
    writer.packFloats(confidence);
  }

  /// Reads pose body data for version 0.1 and 0.2 frames.
  ///
  /// Takes [frames], [shape], [reader], [startFrame], and [endFrame] as parameters.
  /// Returns the read data.
  static dynamic read_v0_1_frames(int frames, List<int> shape,
      BufferReader reader, int? startFrame, int? endFrame) {
    final Struct s = ConstStructs.float;
    int _frames = frames;

    if (startFrame != null && startFrame > 0) {
      if (startFrame >= frames) {
        throw ArgumentError("Start frame is greater than the number of frames");
      }
      reader.advance(s, (startFrame * shape.reduce((a, b) => a * b)));
      _frames -= startFrame;
    }

    int removeFrames = 0;
    if (endFrame != null) {
      endFrame = endFrame > frames ? frames : endFrame;
      removeFrames = frames - endFrame;
      _frames -= removeFrames;
    }

    final List tensor =
        reader.unpackNum(ConstStructs.float, [_frames, ...shape]);
    if (removeFrames != 0) {
      reader.advance(s, (removeFrames * shape.reduce((a, b) => a * b)));
    }

    return tensor;
  }
}

/// Identity matrix of size [n].
List<List<double>> _eye(int n) => [
      for (int i = 0; i < n; i++)
        [for (int j = 0; j < n; j++) i == j ? 1.0 : 0.0]
    ];

/// 2x2 matrix multiplication.
List<List<double>> _matmul2(List<List<double>> a, List<List<double>> b) => [
      for (int i = 0; i < 2; i++)
        [for (int j = 0; j < 2; j++) a[i][0] * b[0][j] + a[i][1] * b[1][j]]
    ];

/// Samples from a normal distribution via the Box-Muller transform.
double _gaussian(Random rng, double mean, double std) {
  final double u1 = 1 - rng.nextDouble(); // in (0, 1]
  final double u2 = rng.nextDouble();
  final double z = sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  return mean + std * z;
}

/// Recursively deep-copies nested lists of numbers.
dynamic _deepCopy(dynamic x) =>
    x is List ? [for (final dynamic e in x) _deepCopy(e)] : x;

/// Builds a 1-D interpolator over `(xs, ys)`: constant for a single point,
/// natural cubic spline when [useCubic] and there are >= 3 points, else linear.
double Function(double) _columnInterpolator(
    List<double> xs, List<double> ys, bool useCubic) {
  if (xs.length == 1) {
    final double v = ys[0];
    return (_) => v;
  }
  if (useCubic) {
    final NaturalCubicSpline spline = NaturalCubicSpline(xs, ys);
    return spline.eval;
  }
  return (double x) => linearInterp(xs, ys, x);
}
