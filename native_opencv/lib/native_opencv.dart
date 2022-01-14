// ignore_for_file: camel_case_types

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

// Load our C lib
final DynamicLibrary nativeLib =
    Platform.isAndroid ? DynamicLibrary.open("libnative_opencv.so") : DynamicLibrary.process();

// C Functions signatures
typedef _c_version = Pointer<Utf8> Function();

// Dart functions signatures
typedef _dart_version = Pointer<Utf8> Function();

// Create dart functions that invoke the C funcion
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
