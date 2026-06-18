import 'dart:convert';
import 'dart:typed_data';

/// Class for writing data to a byte buffer.
///
/// Mirrors [BufferReader] and produces little-endian bytes matching the
/// Python `struct` formats used by the `.pose` file format.
class BufferWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  /// Number of bytes written so far.
  int get length => _builder.length;

  /// Returns the accumulated bytes.
  Uint8List toBytes() => _builder.toBytes();

  /// Packs a 32-bit float (`<f`).
  void packFloat(double value) {
    final ByteData bd = ByteData(4)..setFloat32(0, value, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Packs a 16-bit unsigned short (`<H`).
  void packUShort(int value) {
    final ByteData bd = ByteData(2)..setUint16(0, value, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Packs a 32-bit unsigned integer (`<I`).
  void packUInt(int value) {
    final ByteData bd = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  /// Packs a sequence of unsigned shorts (e.g. `<HH`, `<HHH`).
  void packUShorts(List<int> values) {
    for (final int v in values) {
      packUShort(v);
    }
  }

  /// Packs a string as a ushort length prefix followed by its UTF-8 bytes
  /// (`<H%ds`).
  void packStr(String s) {
    final List<int> bytes = utf8.encode(s);
    packUShort(bytes.length);
    _builder.add(bytes);
  }

  /// Packs a (possibly nested) list of numbers as little-endian float32 in
  /// row-major order. Accepts scalars, or arbitrarily nested [List]s of [num].
  void packFloats(dynamic data) {
    final List<double> flat = [];
    void flatten(dynamic x) {
      if (x is num) {
        flat.add(x.toDouble());
      } else if (x is List) {
        for (final dynamic e in x) {
          flatten(e);
        }
      } else {
        throw ArgumentError('packFloats expects num or nested List<num>, got $x');
      }
    }

    flatten(data);

    final ByteData bd = ByteData(flat.length * 4);
    for (int i = 0; i < flat.length; i++) {
      bd.setFloat32(i * 4, flat[i], Endian.little);
    }
    _builder.add(bd.buffer.asUint8List());
  }

  /// Appends raw bytes to the buffer.
  void packBytes(List<int> bytes) {
    _builder.add(bytes);
  }
}
