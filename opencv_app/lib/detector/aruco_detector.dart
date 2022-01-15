import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:native_opencv/native_opencv.dart';

class ArucoDetector {
  NativeOpencv? _nativeOpencv;

  ArucoDetector() {
    init();
  }

  init() async {
    final bytes = await rootBundle.load('assets/drawable/marker.png');
    final pngBytes = bytes.buffer.asUint8List();

    _nativeOpencv = NativeOpencv();
    _nativeOpencv!.initDetector(pngBytes, 36);
  }

  Float32List? detect(CameraImage image, int rotation) {
    if (_nativeOpencv == null) {
      return null;
    }

    var planes = image.planes;
    var yBuffer = planes[0].bytes;

    Uint8List? uBuffer;
    Uint8List? vBuffer;

    if (Platform.isAndroid) {
      uBuffer = planes[1].bytes;
      vBuffer = planes[2].bytes;
    }

    var res = _nativeOpencv!.detect(image.width, image.height, rotation, yBuffer, uBuffer, vBuffer);
    return res;
  }

  destroy() {
    if (_nativeOpencv != null) {
      _nativeOpencv!.destroy();
      _nativeOpencv = null;
    }
  }
}
