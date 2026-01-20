import 'dart:io';
import 'package:flutter/services.dart';
// UPDATED IMPORT for the new package
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

class BrandingService {
  Future<String?> brandVideo(String inputVideoPath, String assetLogoPath) async {
    try {
      final directory = await getTemporaryDirectory();
      
      // 1. Prepare Logo File from Assets
      final logoFile = File('${directory.path}/watermark_logo.png');
      // Always overwrite to ensure we have the latest asset
      final byteData = await rootBundle.load(assetLogoPath);
      await logoFile.writeAsBytes(byteData.buffer.asUint8List());

      // 2. Define Output Path
      final outputPath = '${directory.path}/branded_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // 3. Construct FFmpeg Command
      // -y : Overwrite output files without asking
      // -i inputVideo -i inputLogo
      // filter_complex: scale the logo to 15% of video height (maintain aspect ratio)
      // overlay: place it W-w-20 (right minus width minus 20px padding) and H-h-20 (bottom)
      final command = 
        "-y -i $inputVideoPath -i ${logoFile.path} "
        "-filter_complex \"[1][0]scale2ref=w=oh*mdar:h=ih*0.15[logo][video];[video][logo]overlay=W-w-20:H-h-20\" "
        "-codec:a copy $outputPath";

      // 4. Execute
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        print("FFmpeg process completed successfully");
        return outputPath;
      } else {
        print("FFmpeg process failed with state ${await session.getState()} and rc $returnCode");
        final logs = await session.getLogs();
        for (var log in logs) {
          print(log.getMessage());
        }
        return null;
      }
    } catch (e) {
      print("Error during video branding: $e");
      return null;
    }
  }
}
