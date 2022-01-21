# Overview
In this tutorial we will go over on how to use OpenCV with flutter to process real-time camera frames in C++.

The Aruco detector we will use can be found [here](https://github.com/ValYouW/ArucoDetector), there is also a [YouTube video](https://www.youtube.com/watch?v=aXB04DleOiE).

Using C/C++ in Flutter is available via [Dart FFI](https://docs.flutter.dev/development/platform-integration/c-interop).

# Get the starter project
This tutorial is built upon a starter app, you can get the starter app by cloning this repo and checking out to tag `tutorial-start-here`.

## The widgets in the starter app
1. `detection_page.dart` - This is the Aruco detector class, it has a single `detect` method that currently does nothing.
1. `detection_page.dart` - This is where we open the camera and display a live feed, main functions:
    1. `initCamera` - Here we open the back camera and register to the camera stream `_camController!.startImageStream((image) => _processCameraImage(image))`
    1. `_processCameraImage` - Here we just call to the aruco detector with the current camera frame.
1. `detections_layer.dart` - This will be the widget that will render the arucos we would find, it will use a `CustomPaint` to do the job.

# Create the native_opencv plugin

`flutter create --platforms=android,ios --template=plugin native_opencv --org com.valyouw`

# Android Studio

Open Android Studio: `native_opencv/example/android`

1. Copy the ArucoDetector to ios/Classes
1. Create native_opencv.cpp in ios/Classes
1. Create a `CMakeLists.txt` under Android/

## CMakeLists:
```
cmake_minimum_required(VERSION 3.10.2)

# opencv
set(OpenCV_STATIC ON)
set(OpenCV_DIR $ENV{OPENCV_ANDROID}/sdk/native/jni)
find_package (OpenCV REQUIRED)

add_library( # Sets the name of the library.
    native_opencv
    SHARED
    # Provides a relative path to your source file(s).
    ../ios/Classes/ArucoDetector/ArucoDetector.cpp
    ../ios/Classes/native_opencv.cpp
)

target_include_directories(
    native_opencv PRIVATE
    ../ios/Classes/ArucoDetector
)

find_library(log-lib log)

target_link_libraries( # Specifies the target library.
    native_opencv
    ${OpenCV_LIBS}
    ${log-lib}
)
```

## Build setup

Open `build.gradle` of native_opencv and add this inside the "android {" section
```
externalNativeBuild {
    cmake {
        path "CMakeLists.txt"
        version "3.10.2"
    }
}
```

1. Run sync - it will fail, in the build log look for **"Minimum required by OpenCV API level is android-21"**
1. Change `minSdkVersion` to 24 in **build.gradle** of native_opencv AND of the **android:app**, there also change `targetSdkVersion` and `compileSdkVersion` to 31
1. Run sync again
1. Check that the "cpp" folder was populated

## native_opencv.cpp
Add this initial code
```
#include <opencv2/core.hpp>
#include "ArucoDetector.h"

using namespace std;
using namespace cv;

static ArucoDetector* detector = nullptr;

void rotateMat(Mat &matImage, int rotation)
{
	if (rotation == 90) {
		transpose(matImage, matImage);
		flip(matImage, matImage, 1); //transpose+flip(1)=CW
	} else if (rotation == 270) {
		transpose(matImage, matImage);
		flip(matImage, matImage, 0); //transpose+flip(0)=CCW
	} else if (rotation == 180) {
		flip(matImage, matImage, -1);    //flip(-1)=180
	}
}

extern "C" {
	// Attributes to prevent 'unused' function from being removed and to make it visible
	__attribute__((visibility("default"))) __attribute__((used))
	const char* version() {
		return CV_VERSION;
	}
}
```

Build the project and show how it compiles the ArucoDetector.cpp

# VSCode
1. Open `native_opencv`
1. Add `ffi: ^1.1.2` to `pubspec.yaml` under `dependencies`
1. Add this to `native_opencv.dart`
```
// Load our C lib
final DynamicLibrary nativeLib =
    Platform.isAndroid ? DynamicLibrary.open("libnative_opencv.so") : DynamicLibrary.process();

// C Functions signatures
typedef _c_version = Pointer<Utf8> Function();

// Dart functions signatures
typedef _dart_version = Pointer<Utf8> Function();

// Create dart functions that invoke the C function
final _version = nativeLib.lookupFunction<_c_version, _dart_version>('version');

class NativeOpencv {
  static const MethodChannel _channel = MethodChannel('native_opencv');

  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  String cvVersion() {
    return _version().toDartString();
  }
}
```

## Use native_opencv in opencv_app
1. Add native_opencv as dep
```
native_opencv:
  path: ../native_opencv
```
1. Add to `main.dart` `main()` method
```
final nativeOpencv = NativeOpencv();
log('--> OpenCV version: ${nativeOpencv.cvVersion()}');
```
1. Run the app and watch the console for output

# Expose ArucoDetector functions
Back in AndroidStudio open `native_opencv.cpp`
```cpp
__attribute__((visibility("default"))) __attribute__((used))
void initDetector(uint8_t* markerPngBytes, int inBytesCount, int bits) {
	if (detector != nullptr) {
		delete detector;
		detector = nullptr;
	}

	vector<uint8_t> buffer(markerPngBytes, markerPngBytes + inBytesCount);
	Mat marker = imdecode(buffer, IMREAD_COLOR);

	detector = new ArucoDetector(marker, bits);
}

__attribute__((visibility("default"))) __attribute__((used))
void destroyDetector() {
	if (detector != nullptr) {
		delete detector;
		detector = nullptr;
	}
}

__attribute__((visibility("default"))) __attribute__((used))
const float* detect(int width, int height, int rotation, uint8_t* bytes, bool isYUV, int32_t* outCount) {
	if (detector == nullptr) {
		float* jres = new float[1];
		jres[0] = 0;
		return jres;
	}

	Mat frame;
	if (isYUV) {
		Mat myyuv(height + height / 2, width, CV_8UC1, bytes);
		cvtColor(myyuv, frame, COLOR_YUV2BGRA_NV21);
	} else {
		frame = Mat(height, width, CV_8UC4, bytes);
	}

	rotateMat(frame, rotation);
	cvtColor(frame, frame, COLOR_BGRA2GRAY);
	vector<ArucoResult> res = detector->detectArucos(frame, 0);

	vector<float> output;

	for (int i = 0; i < res.size(); ++i) {
		ArucoResult ar = res[i];
		// each aruco has 4 corners
		output.push_back(ar.corners[0].x);
		output.push_back(ar.corners[0].y);
		output.push_back(ar.corners[1].x);
		output.push_back(ar.corners[1].y);
		output.push_back(ar.corners[2].x);
		output.push_back(ar.corners[2].y);
		output.push_back(ar.corners[3].x);
		output.push_back(ar.corners[3].y);
	}

	// Copy result bytes as output vec will get freed
	unsigned int total = sizeof(float) * output.size();
	float* jres = (float*)malloc(total);
	memcpy(jres, output.data(), total);

	*outCount = output.size();
	return jres;
}
```
And now in `native_opencv.dart` in VSCode define the C Functions
```dart
typedef _c_initDetector = Void Function(Pointer<Uint8> markerPngBytes, Int32 inSize, Int32 bits);
typedef _c_destroyDetector = Void Function();
typedef _c_detect = Pointer<Float> Function(
    Int32 width, Int32 height, Int32 rotation, Pointer<Uint8> bytes, Bool isYUV, Pointer<Int32> outCount);
```
And the Dart Functions
```dart
typedef _dart_version = Pointer<Utf8> Function();
typedef _dart_initDetector = void Function(Pointer<Uint8> markerPngBytes, int inSize, int bits);
typedef _dart_destroyDetector = void Function();
typedef _dart_detect = Pointer<Float> Function(
    int width, int height, int rotation, Pointer<Uint8> bytes, bool isYUV, Pointer<Int32> outCount);
```
And finally associate the functions
```dart
final _initDetector = nativeLib.lookupFunction<_c_initDetector, _dart_initDetector>('initDetector');
final _destroyDetector = nativeLib.lookupFunction<_c_destroyDetector, _dart_destroyDetector>('destroyDetector');
final _detect = nativeLib.lookupFunction<_c_detect, _dart_detect>('detect');
```

And inside `class NativeOpencv` define the methods that will be exposed to our app:
```dart
void initDetector(Uint8List markerPngBytes, int bits) {
  var totalSize = markerPngBytes.lengthInBytes;
  var imgBuffer = malloc.allocate<Uint8>(totalSize);
  Uint8List bytes = imgBuffer.asTypedList(totalSize);
  bytes.setAll(0, markerPngBytes);

  _initDetector(imgBuffer, totalSize, bits);

  //// todo: Should delete imgBuffer ??
}

void destroy() {
  _destroyDetector();
}

Float32List detect(int width, int height, int rotation, Uint8List yBuffer, Uint8List? uBuffer, Uint8List? vBuffer) {
  var ySize = yBuffer.lengthInBytes;
  var uSize = uBuffer?.lengthInBytes ?? 0;
  var vSize = vBuffer?.lengthInBytes ?? 0;
  var totalSize = ySize + uSize + vSize;

  _imageBuffer ??= malloc.allocate<Uint8>(totalSize);

  // We always have at least 1 plane, on Android it si the yPlane on iOS its the rgba plane
  Uint8List _bytes = _imageBuffer!.asTypedList(totalSize);
  _bytes.setAll(0, yBuffer);

  if (Platform.isAndroid) {
    // Swap u&v buffer for opencv
    _bytes.setAll(ySize, vBuffer!);
    _bytes.setAll(ySize + vSize, uBuffer!);
  }

  Pointer<Int32> outCount = malloc.allocate<Int32>(1);
  var res = _detect(width, height, rotation, _imageBuffer!, Platform.isAndroid ? true : false, outCount);
  final count = outCount.value;

  //// todo: Should delete outCount ??
  return res.asTypedList(count);
}
```

# Use native_opencv plugin in flutter app

## ArucoDetector class
In `aruco_detector.dart` this is the implementation:
```dart
class ArucoDetector {
  NativeOpencv? _nativeOpencv;

  ArucoDetector() {
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
```

## Call detection on each camera frame
In `detection_page.dart` add these 2 members to `_DetectionPageState`:
```dart
double _camFrameToScreenScale = 0;
List<double> _arucos = List.empty();
```
Then this is the updated `_processCameraImage` method:
```dart
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
```

# Drawing the Aruco results on DetectionsLayer
We will use a CustomPainter to draw the arucos, in `detections_layer.dart` implement the build method as:
```dart
@override
Widget build(BuildContext context) {
  return CustomPaint(
    painter: ArucosPainter(arucos: arucos),
  );
}
```
And create the `ArucosPainer` class:
```dart
class ArucosPainter extends CustomPainter {
  ArucosPainter({required this.arucos});

  // list of aruco coordinates, each aruco has 4 corners with x/y, total of 8 numbers per aruco
  final List<double> arucos;

  // paint we will use to draw to arucos
  final _paint = Paint()
    ..strokeWidth = 2.0
    ..color = Colors.red
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (arucos.isEmpty) {
      return;
    }

    // Each aruco is 8 numbers (4 corners * x,y) and corners are starting from
    // top-left going clockwise
    final count = arucos.length ~/ 8;
    for (int i = 0; i < count; ++i) {
      // where current aruco coords starts
      int arucoIdx = i * 8;

      // Draw the 4 lines of the aruco
      for (int j = 0; j < 4; ++j) {
        // each corner has x and y so we jump in 2
        final corner1Idx = arucoIdx + j * 2;

        // since the corners are clockwise we can take the next corner by adding 1 to j
        // making sure not to overflow to the next aruco, hence the modulo 8, so when
        // j=3 corner1 will be the bottom-left corner, and corner2 will be the top-left (like j=0)
        final corner2Idx = arucoIdx + ((j + 1) * 2) % 8;

        // Draw the line between the 2 corners
        final from = Offset(arucos[corner1Idx], arucos[corner1Idx + 1]);
        final to = Offset(arucos[corner2Idx], arucos[corner2Idx + 1]);
        canvas.drawLine(from, to, _paint);
      }
    }
  }

  @override
  bool shouldRepaint(ArucosPainter oldDelegate) {
    // We check if the arucos array was changed, if so we should re-paint
    if (arucos.length != oldDelegate.arucos.length) {
      return true;
    }

    for (int i = 0; i < arucos.length; ++i) {
      if (arucos[i] != oldDelegate.arucos[i]) {
        return true;
      }
    }

    return false;
  }
}
```

# Running detection on background thread
Currently our detection runs on the main (ui) thread and we should avoid running intensive work on the ui thread, so lets run our detector on a separate thread, or as it is called in Dart - Isolate.

## Changes to `aruco_detector.dart`
We will convert this file to be the entry point of our new Isolate.

1. Convert the `ArucoDetector` class to be private by renaming it to `_ArucoDetector`. This class will only be used locally int his file.
1. Add the Request/Response classes that will be sent between the
```dart
// This class will be used as argument to the init method, since we cant access the bundled assets
// from an Isolate we must get the marker png from the main thread
class InitRequest {
  SendPort toMainThread;
  ByteData markerPng;
  InitRequest({required this.toMainThread, required this.markerPng});
}

// this is the class that the main thread will send here asking to invoke a function on ArucoDetector
class Request {
  // a correlation id so the main thread will be able to match response with request
  int reqId;
  String method;
  dynamic params;
  Request({required this.reqId, required this.method, this.params});
}

// this is the class that will be sent as a response to the main thread
class Response {
  int reqId;
  dynamic data;
  Response({required this.reqId, this.data});
}

// This is the port that will be used to send data to main thread
late SendPort _toMainThread;
late _ArucoDetector _detector;
```

Next lets write the function that will be the entry point when the main thread will invoke a new Isolate:
```dart
void init(InitRequest initReq) {
  // Create ArucoDetector
  _detector = _ArucoDetector(initReq.markerPng);

  // Save the port on which we will send messages to the main thread
  _toMainThread = initReq.toMainThread;

  // Create a port on which the main thread can send us messages and listen to it
  ReceivePort fromMainThread = ReceivePort();
  fromMainThread.listen(_handleMessage);

  // Send the main thread the port on which it can send us messages
  _toMainThread.send(fromMainThread.sendPort);
}
```
And change `_ArucoDetector` to receive the marker png in its constructor and pass it on to its `init` method:
```dart
_ArucoDetector(ByteData markerPng) {
  init(markerPng);
}

init(ByteData markerPng) async {
  // Note our c++ init detector code expects marker to be in png format
  final pngBytes = markerPng.buffer.asUint8List();
  ...
}
```

## ArucoDetector wrapper
In order to prevent the detection page of handling the background thread lets create a wrapper around ArucoDetector that will do that. We call it `ArucoDetectorAsync`

Create a file `aruco_detector_async.dart`
```dart
import 'dart:async';
import 'dart:developer';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:opencv_app/detector/aruco_detector.dart' as aruco_detector;

class ArucoDetectorAsync {
  bool arThreadReady = false;
  late Isolate _detectorThread;
  late SendPort _toDetectorThread;
  int _reqId = 0;
  final Map<int, Completer> _cbs = {};

  ArucoDetectorAsync() {
    _initDetectionThread();
  }

  void _initDetectionThread() async {
    // Create the port on which the detector thread will send us messages and listen to it.
    ReceivePort fromDetectorThread = ReceivePort();
    fromDetectorThread.listen(_handleMessage, onDone: () {
      arThreadReady = false;
    });

    // Spawn a new Isolate using the ArucoDetector.init method as entry point and
    // the port on which it can send us messages as parameter
    _detectorThread = await Isolate.spawn(aruco_detector.init, fromDetectorThread.sendPort);
  }

  Future<Float32List?> detect(CameraImage image, int rotation) {
    if (!arThreadReady) {
      return Future.value(null);
    }

    var reqId = ++_reqId;
    var res = Completer<Float32List?>();
    _cbs[reqId] = res;
    var msg = aruco_detector.Request(
      reqId: reqId,
      method: 'detect',
      params: {'image': image, 'rotation': rotation},
    );

    _toDetectorThread.send(msg);
    return res.future;
  }

  void destroy() async {
    if (!arThreadReady) {
      return;
    }

    arThreadReady = false;

    // We send a Destroy request and wait for a response before killing the thread
    var reqId = ++_reqId;
    var res = Completer();
    _cbs[reqId] = res;
    var msg = aruco_detector.Request(reqId: reqId, method: 'destroy');
    _toDetectorThread.send(msg);

    // Wait for the detector to acknoledge the destory and kill the thread
    await res.future;
    _detectorThread.kill();
  }

  void _handleMessage(data) {
    // The detector thread send us its SendPort on init, if we got it this means the detector is ready
    if (data is SendPort) {
      _toDetectorThread = data;
      arThreadReady = true;
      return;
    }

    // Make sure we got a Response object
    if (data is aruco_detector.Response) {
      // Find the Completer associated with this request and resolve it
      var reqId = data.reqId;
      _cbs[reqId]?.complete(data.data);
      _cbs.remove(reqId);
      return;
    }

    log('Unknown message from ArucoDetector, got: $data');
  }
}
```

## Use ArucoDetectorAsync
In `detection_page.dart` use `ArucoDetectorAsync` instead of `ArucoDetector`
1. Replace the definition and initialization of `_arucoDetecor` with `ArucoDetectorAsync`
1. Introduce a new class variable `bool _detectionInProgress = false;` - because detection is async now we need to make sure not to call it while it is already running
1. In `_processCameraImage`:
    1. use `_detectionInProgress` in the first `if` so it becomes: `if (_detectionInProgress || !mounted || ...`
	1. use `await` when calling to `detect` and set `_detectionInProgress` to true/false before/after calling detect, and make sure we are still mounted before handling the result:
	```dart
    // Call the detector
    _detectionInProgress = true;
    var res = await _arucoDetector.detect(image, _camFrameRotation);
    _detectionInProgress = false;
    _lastRun = DateTime.now().millisecondsSinceEpoch;

    // Make sure we are still mounted, the background thread can return a response after we navigate away from this
    // screen but before bg thread is killed
    if (!mounted || res == null || res.isEmpty) {
      return;
    }
	```
# THE END
