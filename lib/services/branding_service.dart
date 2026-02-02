import 'dart:io';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';

class BrandingService {
  Future<String?> brandVideo(String inputVideoPath, String assetLogoPath) async {
    try {
      final directory = await getTemporaryDirectory();
      
      // 1. Write the asset logo to a temp file so FFmpeg can read it
      final logoFile = File('${directory.path}/watermark_logo.png');
      final byteData = await rootBundle.load(assetLogoPath);
      await logoFile.writeAsBytes(byteData.buffer.asUint8List());

      // 2. Create a unique output path
      final outputPath = '${directory.path}/branded_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // 3. FFmpeg Command
      // [1][0]scale2ref... : Scales logo to 15% of video height
      // overlay=W-w-20:H-h-20 : Places it in bottom-right with 20px padding
      final command = 
        "-y -i $inputVideoPath -i ${logoFile.path} "
        "-filter_complex \"[1][0]scale2ref=w=oh*mdar:h=ih*0.15[logo][video];[video][logo]overlay=W-w-20:H-h-20\" "
        "-codec:a copy $outputPath";

      print("Starting FFmpeg processing...");
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        print("FFmpeg Success: $outputPath");
        return outputPath;
      } else {
        print("FFmpeg Failed. Return Code: $returnCode");
        // Print logs to see why it failed
        final logs = await session.getLogs();
        for (var log in logs) {
          print(log.getMessage());
        }
        return null;
      }
    } catch (e) {
      print("Branding Service Error: $e");
      return null;
    }
  }
}
