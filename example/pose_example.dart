import 'dart:io';
import 'dart:typed_data';
import 'package:pose/pose.dart';

void main() {
  File file = File("pose_file.pose");
  Uint8List fileContent = file.readAsBytesSync();
  print("File Read");

  Pose pose = Pose.read(fileContent);
  print("File Loaded");

  PoseVisualizer p = PoseVisualizer(pose);
  print("File Visualized");

  p.saveGif("demo.gif", p.draw());
  print("File Saved");
}
