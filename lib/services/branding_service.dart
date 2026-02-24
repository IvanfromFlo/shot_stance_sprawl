import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BrandingService {
  static const MethodChannel _channel = MethodChannel('com.yourname.shot_stance_sprawl/watermark');

  /// Applies a watermark to the video. Returns the new path or null on failure.
  Future<String?> applyBranding({
    required String inputVideoPath, 
    required String assetLogoPath,
    required bool isPremium,
  }) async {
    // 1. Pro users skip this entirely
    if (isPremium) return inputVideoPath; 

    // 2. Validate input
    if (inputVideoPath.isEmpty) return null;
    final inputFile = File(inputVideoPath);
    if (!await inputFile.exists()) {
      debugPrint("BrandingService Error: Input file does not exist at $inputVideoPath");
      return null;
    }

    try {
      // 3. Call Native
      final String? outputPath = await _channel.invokeMethod('addWatermark', {
        'videoPath': inputVideoPath,
        'watermarkAsset': assetLogoPath, 
      });

      // 4. Validate output
      if (outputPath == null || outputPath == inputVideoPath) {
        debugPrint("BrandingService Error: Native returned null or bypassed branding.");
        return null; 
      }

      final outputFile = File(outputPath);
      if (await outputFile.exists() && await outputFile.length() > 0) {
        return outputPath;
      }
      
      debugPrint("BrandingService Error: Output file is missing or empty.");
      return null;
    } on PlatformException catch (e) {
      debugPrint("BrandingService Native Exception: ${e.code} - ${e.message}");
      return null; 
    } catch (e) {
      debugPrint("BrandingService General Error: $e");
      return null; 
    }
  }
}