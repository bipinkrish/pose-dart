import 'package:pose/src/masked_array.dart';
import 'package:pose/src/representation.dart';

/// Computes optical flow between consecutive frames as the per-point distance
/// travelled, normalized by [fps]. Mirrors Python
/// `pose_format.utils.optical_flow.OpticalFlowCalculator`.
class OpticalFlowCalculator {
  final double fps;

  /// Distance between two point sets along the last axis. Defaults to
  /// Euclidean ([DistanceRepresentation]).
  final MaskedArray Function(MaskedArray, MaskedArray) distance;

  OpticalFlowCalculator(this.fps,
      {MaskedArray Function(MaskedArray, MaskedArray)? distance})
      : distance = distance ?? DistanceRepresentation().call;

  /// [src] is shaped `(frames, ..., dims)`; returns `(frames-1, ...)` flow
  /// magnitudes, scaled by [fps].
  MaskedArray call(MaskedArray src) {
    final int n = src.shape[0];
    final MaskedArray pre =
        src.gatherFirst([for (int i = 0; i < n - 1; i++) i]);
    final MaskedArray post = src.gatherFirst([for (int i = 1; i < n; i++) i]);
    return distance(post, pre).multiply(fps);
  }
}
