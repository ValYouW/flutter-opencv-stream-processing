import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:native_opencv/native_opencv.dart';

class Request {
  int reqId;
  String method;
  dynamic params;
  Request({required this.reqId, required this.method, this.params});
}

class Response {
  int reqId;
  dynamic data;
  Response({required this.reqId, this.data});
}

late SendPort _toMainThread;
late _ArucoDetector _detector;

void init(SendPort toMainThread) {
  // Create ArucoDetector
  _detector = _ArucoDetector();

  // Save the port on which we will send messages to the main thread
  _toMainThread = toMainThread;

  // Create a port on which the main thread can send us messages and listen to it
  ReceivePort fromMainThread = ReceivePort();
  fromMainThread.listen(_handleMessage);

  // Send the main thread the port on which it can send us messages
  _toMainThread.send(fromMainThread.sendPort);
}

void _handleMessage(data) {
  if (data is Request) {
    dynamic res;
    switch (data.method) {
      case 'detect':
        var image = data.params['image'] as CameraImage;
        var rotation = data.params['rotation'];
        res = _detector.detect(image, rotation);
        break;
      case 'destroy':
        _detector.destroy();
        break;
    }

    _toMainThread.send(Response(reqId: data.reqId, data: res));
  }
}

class _ArucoDetector {
  NativeOpencv? _nativeOpencv;

  _ArucoDetector() {
    init();
  }

  init() async {
    // Read the marker template from the assets folder, note it is read in png format which is what
    // our c++ init detector code expects
    final bytes = await rootBundle.load('assets/drawable/marker.png');
    final pngBytes = bytes.buffer.asUint8List();

    // init the detector
    _nativeOpencv = NativeOpencv();
    _nativeOpencv!.initDetector(pngBytes, 36);
  }

  Float32List? detect(CameraImage image, int rotation) {
    // make sure we have a detector
    if (_nativeOpencv == null) {
      return null;
    }

    // On Android the image format is YUV and we get a buffer per channel,
    // in iOS the format is BGRA and we get a single buffer for all channels.
    // So the yBuffer variable on Android will be just the Y channel but on iOS it will be
    // the entire image
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
