import 'dart:io';
import 'dart:typed_data';
import 'package:pose/pose.dart';

void main() {
  File file = File("pose_file.pose");
  Uint8List fileContent = file.readAsBytesSync();
  Pose pose = Pose.read(fileContent);
  print(pose.body.fps);
}
