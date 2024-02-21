import 'dart:convert';
import 'dart:typed_data';

import 'package:pose/numdart.dart' show Struct, ConstStructs;
import 'package:pose/numdart.dart' as nd;

class BufferReader {
  Uint8List buffer;
  int readOffset;

  BufferReader(this.buffer) : readOffset = 0;

  int bytesLeft() {
    return buffer.length - readOffset;
  }

  Uint8List unpackF(int size) {
    Uint8List data = buffer.sublist(readOffset, readOffset + size);
    advance(Struct("<>", size));
    return data;
  }

  List<dynamic> unpackNumpy(Struct s, List<int> shape) {
    List<dynamic> arr = nd.ndarray(shape, s, buffer, readOffset);
    int arrayBufferSize = nd.prod(shape);
    advance(s, arrayBufferSize);

    return arr;
  }

  dynamic unpack(Struct s) {
    Uint8List data = buffer.sublist(readOffset, readOffset + s.size);
    advance(s);

    List<dynamic> result = [];

    if (s.format == "<f") {
      result.add(nd.bytesToFloat(data));
    } else if (s.format == "<h") {
      result.add(nd.bytesToInt(data, signed: true));
    } else if (["<H", "<HH", "<HHH"].contains(s.format)) {
      for (int i = 0; i < data.length; i += 2) {
        result.add(nd.bytesToInt(data.sublist(i, i + 2)));
      }
    } else {
      throw ArgumentError("Invalid format.");
    }

    if (result.length == 1) {
      return result[0];
    }
    return result;
  }

  void advance(Struct s, [int times = 1]) {
    readOffset += s.size * times;
  }

  String unpackStr() {
    int length = unpack(ConstStructs.ushort);
    Uint8List bytes_ = unpackF(length);
    return utf8.decode(bytes_);
  }
}
