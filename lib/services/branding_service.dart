import 'dart:io';
import 'package:flutter/services.dart';

class BrandingService {
  // Method Channel pointing to native implementations
  static const MethodChannel _channel = MethodChannel('com.yourname.shot_stance_sprawl/watermark');

  /// Applies a watermark to the video via Native Platform Channels (Android Media3 / iOS AVFoundation).
  /// If [isPremium] is true, bypasses entirely and passes the raw video back.
  Future<String?> applyBranding({
    required String inputVideoPath, 
    required String assetLogoPath,
    required bool isPremium,
  }) async {
    // FREEMIUM GATING: Paid version skips watermark processing entirely
    if (isPremium) {
      return inputVideoPath; 
    }

    if (inputVideoPath.isEmpty || !File(inputVideoPath).existsSync()) {
      return inputVideoPath; 
    }

    try {
      // Calls the native platform code to apply the watermark using hardware acceleration.
      final String? outputPath = await _channel.invokeMethod('addWatermark', {
        'videoPath': inputVideoPath,
        'watermarkAsset': assetLogoPath, 
      });

      if (outputPath != null && File(outputPath).existsSync()) {
        return outputPath;
      }
      
      return inputVideoPath;
    } catch (e) {
      print("Native Watermark Error: $e");
      // Fallback to the raw video rather than losing the user's workout entirely.
      return inputVideoPath; 
    }
  }
}