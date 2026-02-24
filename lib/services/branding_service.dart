import 'dart:io';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

class BrandingService {
  /// Applies a watermark to the video.
  /// If [isPremium] is true, bypasses FFmpeg entirely and passes the raw video back.
  Future<String?> applyBranding({
    required String inputVideoPath, 
    required String assetLogoPath,
    required bool isPremium,
  }) async {
    // FREEMIUM GATING: Paid version skips watermark processing entirely
    if (isPremium) {
      print("Premium Tier Detected: Skipping watermark overlay.");
      return inputVideoPath; 
    }

    // 1. SAFETY CHECK: Ensure the file actually exists and isn't a broken path
    if (inputVideoPath.isEmpty || !File(inputVideoPath).existsSync()) {
      print("Branding Service Error: Input video missing or invalid at: $inputVideoPath");
      return inputVideoPath; // Return raw (or null) so the app doesn't crash
    }

    try {
      final directory = await getTemporaryDirectory();
      
      // 2. Write the asset logo to a temp file so FFmpeg can read it
      final logoFile = File('${directory.path}/watermark_logo.png');
      final byteData = await rootBundle.load(assetLogoPath);
      await logoFile.writeAsBytes(byteData.buffer.asUint8List());

      // 3. Create a unique output path
      final outputPath = '${directory.path}/branded_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // 4. OPTIMIZED FFmpeg Command
      // -y: overwrite existing
      // -preset ultrafast: CRITICAL for mobile to not freeze the app for 3+ minutes
      // -crf 28: Good balance of quality and file size for fast exporting
      final command = 
        "-y -i \"$inputVideoPath\" -i \"${logoFile.path}\" "
        "-filter_complex \"[1][0]scale2ref=w=oh*mdar:h=ih*0.15[logo][video];[video][logo]overlay=W-w-20:H-h-20\" "
        "-c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \"$outputPath\"";

      print("Free Tier: Starting FAST FFmpeg processing to apply watermark...");
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        print("FFmpeg Success: Watermarked video saved to $outputPath");
        return outputPath;
      } else {
        print("FFmpeg Failed. Return Code: $returnCode");
        
        // Output failure logs for debugging
        final logs = await session.getLogs();
        for (var log in logs) {
          print(log.getMessage());
        }
        // Critical: Fallback to the raw video rather than returning null and losing the workout.
        return inputVideoPath;
      }
    } catch (e) {
      print("Branding Service Exception: $e");
      return inputVideoPath; // Fallback on hard exception
    }
  }
}