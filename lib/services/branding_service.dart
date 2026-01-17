// lib/services/branding_service.dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:watermark_kit/watermark_kit.dart';

class BrandingService {
  final _wm = WatermarkKit();

  Future<String?> brandVideo(String inputPath, String assetPath) async {
    try {
      // 1. Load your logo from assets
      final ByteData byteData = await rootBundle.load(assetPath);
      final Uint8List logoBytes = byteData.buffer.asUint8List();

      // 2. Start the native watermarking task
      final task = await _wm.composeVideo(
        inputVideoPath: inputPath,
        watermarkImage: logoBytes,
        anchor: 'bottomRight',
        widthPercent: 0.15,
        opacity: 0.8,
      );

      // 3. Wait for the native side to finish and return the new path
      final String brandedPath = await task.done;
      return brandedPath;
    } catch (e) {
      print("Error during branding: $e");
      return null;
    }
  }
}