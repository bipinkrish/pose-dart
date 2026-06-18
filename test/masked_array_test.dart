import 'package:pose/src/masked_array.dart';
import 'package:test/test.dart';

void expectNested(dynamic a, dynamic b, {double eps = 1e-9}) {
  if (a is List && b is List) {
    expect(a.length, equals(b.length));
    for (int i = 0; i < a.length; i++) {
      expectNested(a[i], b[i], eps: eps);
    }
  } else if (a is num && b is num) {
    expect(a.toDouble(), closeTo(b.toDouble(), eps));
  } else {
    fail('type mismatch: $a vs $b');
  }
}

void main() {
  group('construction', () {
    test('fromNested shape + round-trip', () {
      final m = MaskedArray.fromNested([
        [1, 2, 3],
        [4, 5, 6]
      ]);
      expect(m.shape, equals([2, 3]));
      expect(m.size, equals(6));
      expectNested(m.toNested(), [
        [1, 2, 3],
        [4, 5, 6]
      ]);
    });

    test('fromPose masks zero-confidence points across dims', () {
      final m = MaskedArray.fromPose([
        [
          [
            [1, 2],
            [3, 4]
          ]
        ]
      ], [
        [
          [0.5, 0]
        ]
      ]);
      expect(m.shape, equals([1, 1, 2, 2]));
      expect(m.mask.toList(), equals([0, 0, 1, 1]));
    });
  });

  group('elementwise + broadcasting', () {
    test('scalar multiply', () {
      final m = MaskedArray.fromNested([
        [1, 2],
        [3, 4]
      ]).multiply(2);
      expectNested(m.toNested(), [
        [2, 4],
        [6, 8]
      ]);
    });

    test('broadcast subtract (2,3) - (3,)', () {
      final a = MaskedArray.fromNested([
        [10, 20, 30],
        [40, 50, 60]
      ]);
      final b = MaskedArray.fromNested([1, 2, 3]);
      expectNested(a.subtract(b).toNested(), [
        [9, 18, 27],
        [39, 48, 57]
      ]);
    });

    test('mask propagates through binary op', () {
      final a = MaskedArray.fromPose([
        [
          [
            [1, 1],
            [2, 2]
          ]
        ]
      ], [
        [
          [1, 0]
        ]
      ]); // point1 masked
      final r = a.add(1);
      expect(r.mask.toList(), equals([0, 0, 1, 1]));
    });
  });

  group('reductions (mask-aware)', () {
    test('mean over axis 0 and 1', () {
      final m = MaskedArray.fromNested([
        [1, 2, 3],
        [4, 5, 6]
      ]);
      expectNested(m.mean({0}).toNested(), [2.5, 3.5, 4.5]);
      expectNested(m.mean({1}).toNested(), [2, 5]);
      expect(m.mean().scalar, closeTo(3.5, 1e-9));
    });

    test('std is population (ddof=0)', () {
      final m = MaskedArray.fromNested([1, 2, 3, 4]);
      expect(m.std().scalar, closeTo(1.1180339887, 1e-7));
    });

    test('reductions ignore masked entries', () {
      final m = MaskedArray.fromPose([
        [
          [
            [1],
            [3]
          ],
          [
            [2],
            [99]
          ]
        ]
      ], [
        [
          [1, 1],
          [1, 0]
        ]
      ]); // last point (value 99) masked
      // shape (1,2,2,1); mean over frames+people+points -> dims
      expect(m.mean({0, 1, 2}).scalar, closeTo((1 + 3 + 2) / 3, 1e-9));
      expect(m.max({0, 1, 2}).scalar, closeTo(3, 1e-9));
    });

    test('all-masked cell becomes masked', () {
      final m = MaskedArray.fromPose([
        [
          [
            [5, 5]
          ]
        ]
      ], [
        [
          [0]
        ]
      ]);
      final r = m.mean({0, 1, 2});
      expect(r.mask.toList(), equals([1, 1]));
    });
  });

  group('shape ops', () {
    test('permute = transpose (2,3)->(3,2)', () {
      final m = MaskedArray.fromNested([
        [1, 2, 3],
        [4, 5, 6]
      ]).permute([1, 0]);
      expect(m.shape, equals([3, 2]));
      expectNested(m.toNested(), [
        [1, 4],
        [2, 5],
        [3, 6]
      ]);
    });

    test('points_perspective-style 4D permute round-trips', () {
      final original = MaskedArray.fromNested([
        [
          [
            [1, 2],
            [3, 4]
          ],
          [
            [5, 6],
            [7, 8]
          ]
        ]
      ]); // (1,2,2,2) = (F,P,N,D)
      final t = original.permute([2, 1, 0, 3]); // (N,P,F,D)
      expect(t.shape, equals([2, 2, 1, 2]));
      final back = t.permute([2, 1, 0, 3]);
      expectNested(back.toNested(), original.toNested());
    });

    test('takeFirst and gatherFirst', () {
      final m = MaskedArray.fromNested([
        [1, 2],
        [3, 4],
        [5, 6]
      ]);
      expectNested(m.takeFirst(1).toNested(), [3, 4]);
      expectNested(m.gatherFirst([2, 0]).toNested(), [
        [5, 6],
        [1, 2]
      ]);
    });
  });

  group('matmul', () {
    test('identity returns input', () {
      final m = MaskedArray.fromNested([
        [1, 2],
        [3, 4]
      ]);
      expectNested(
          m.matmul([
            [1, 0],
            [0, 1]
          ]).toNested(),
          [
            [1, 2],
            [3, 4]
          ]);
    });

    test('column swap', () {
      final m = MaskedArray.fromNested([
        [1, 2],
        [3, 4]
      ]);
      expectNested(
          m.matmul([
            [0, 1],
            [1, 0]
          ]).toNested(),
          [
            [2, 1],
            [4, 3]
          ]);
    });
  });
}
