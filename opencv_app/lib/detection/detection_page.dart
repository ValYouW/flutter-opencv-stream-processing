import 'dart:developer';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:opencv_app/detection/detections_layer.dart';
import 'package:opencv_app/detector/aruco_detector.dart';

class DetectionPage extends StatefulWidget {
  const DetectionPage({Key? key}) : super(key: key);

  @override
  _DetectionPageState createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> with WidgetsBindingObserver {
  CameraController? _camController;
  late ArucoDetector _arucoDetector;
  int _camFrameRotation = 0;
  double _camFrameToScreenScale = 0;
  int _lastRun = 0;
  List<double> _arucos = List.empty();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance?.addObserver(this);
    _arucoDetector = ArucoDetector();
    initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _camController;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance?.removeObserver(this);
    _arucoDetector.destroy();
    _camController?.dispose();
    super.dispose();
  }

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    var idx = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (idx < 0) {
      log("No Back camera found - weird");
      return;
    }

    var desc = cameras[idx];
    _camFrameRotation = Platform.isAndroid ? desc.sensorOrientation : 0;
    _camController = CameraController(
      desc,
      ResolutionPreset.high, // 720p
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );

    try {
      await _camController!.initialize();
      await _camController!.startImageStream((image) => _processCameraImage(image));
    } catch (e) {
      log("Error initializing camera, error: ${e.toString()}");
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (!mounted || DateTime.now().millisecondsSinceEpoch - _lastRun < 30) {
      return;
    }

    // calc the scale factor to convert from camera frame coords to screen coords.
    // NOTE!!!! We assume camera frame takes the entire screen width, if that's not the case
    // (like if camera is landscape or the camera frame is limited to some area) then you will
    // have to find the correct scale factor somehow else
    if (_camFrameToScreenScale == 0) {
      var w = (_camFrameRotation == 0 || _camFrameRotation == 180) ? image.width : image.height;
      _camFrameToScreenScale = MediaQuery.of(context).size.width / w;
    }

    // Call the detector
    var res = _arucoDetector.detect(image, _camFrameRotation);
    _lastRun = DateTime.now().millisecondsSinceEpoch;

    if (res == null || res.isEmpty) {
      return;
    }

    // Check that the number of coords we got divides by 8 exactly, each aruco has 8 coords (4 corners x/y)
    if ((res.length / 8) != (res.length ~/ 8)) {
      log('Got invalid response from ArucoDetector, number of coords is ${res.length} and does not represent complete arucos with 4 corners');
      return;
    }

    // convert arucos from camera frame coords to screen coords
    final arucos = res.map((x) => x * _camFrameToScreenScale).toList(growable: false);
    setState(() {
      _arucos = arucos;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_camController == null) {
      return const Center(
        child: Text('Loading...'),
      );
    }

    return Stack(
      children: [
        CameraPreview(_camController!),
        DetectionsLayer(
          arucos: _arucos,
        ),
      ],
    );
  }
}
