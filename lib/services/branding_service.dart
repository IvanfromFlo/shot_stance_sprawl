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
      return inputVideoPath; 
    }

    // SAFETY CHECK: Ensure the file actually exists and isn't a broken path
    if (inputVideoPath.isEmpty || !File(inputVideoPath).existsSync()) {
      return inputVideoPath; // Return raw so the app doesn't crash
    }

    try {
      final directory = await getTemporaryDirectory();
      
      // Write the asset logo to a temp file so FFmpeg can read it
      final logoFile = File('${directory.path}/watermark_logo.png');
      final byteData = await rootBundle.load(assetLogoPath);
      await logoFile.writeAsBytes(byteData.buffer.asUint8List());

      final outputPath = '${directory.path}/branded_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // OPTIMIZED FFmpeg Command
      // -preset ultrafast: CRITICAL for mobile to not freeze the app
      final command = 
        "-y -i \"$inputVideoPath\" -i \"${logoFile.path}\" "
        "-filter_complex \"[1][0]scale2ref=w=oh*mdar:h=ih*0.15[logo][video];[video][logo]overlay=W-w-20:H-h-20\" "
        "-c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \"$outputPath\"";

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      // ARCHIVAL FALLBACK: Since FFmpegKit is archived, if it fails due to 
      // modern OS restrictions, we MUST fallback to the original video.
      if (ReturnCode.isSuccess(returnCode)) {
        return outputPath;
      } else {
        // Fallback to the raw video rather than returning null and losing the workout.
        return inputVideoPath;
      }
    } catch (e) {
      return inputVideoPath; // Hard Exception Fallback
    }
  }
}