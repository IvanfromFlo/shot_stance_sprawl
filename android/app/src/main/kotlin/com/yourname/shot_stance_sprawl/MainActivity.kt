package com.yourname.shot_stance_sprawl

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.yourname.shot_stance_sprawl/watermark"

    @OptIn(UnstableApi::class)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "addWatermark") {
                val inputPath = call.argument<String>("videoPath")
                val assetPath = call.argument<String>("watermarkAsset")

                if (inputPath == null || assetPath == null) {
                    result.error("INVALID_ARGS", "Missing arguments", null)
                    return@setMethodCallHandler
                }

                val loader = io.flutter.FlutterInjector.instance().flutterLoader()
                val key = loader.getLookupKeyForAsset(assetPath)

                // FIX: Ensure we use the application context for asset access to avoid leaks
                val bitmap: Bitmap? = try {
                    context.assets.open(key).use { inputStream ->
                        // The 'use' block ensures the inputStream is safely closed after decoding
                        BitmapFactory.decodeStream(inputStream)
                    }
                } catch (e: Exception) {
                    null
                }

                // Prevent the Media3 Transformer from starting if the asset failed to load
                if (bitmap == null) {
                    result.error("ASSET_ERROR", "Watermark asset not found: $key", null)
                    return@setMethodCallHandler
}
                // FIX: Scoped to filesDir to ensure persistent hardware encoder write access
                val outputDir = File(context.filesDir, "branded_videos")
                if (!outputDir.exists()) outputDir.mkdirs()
                val outputPath = File(outputDir, "watermarked_${System.currentTimeMillis()}.mp4").absolutePath

                val overlay = object : BitmapOverlay() {
                    override fun getBitmap(presentationTimeUs: Long): Bitmap {
                        return bitmap
                    }
                }

                val overlayEffect = OverlayEffect(ImmutableList.of<TextureOverlay>(overlay))
                
                val audioProcessors = mutableListOf<AudioProcessor>()
                val videoEffects = mutableListOf<Effect>(overlayEffect)
                val effects = Effects(audioProcessors, videoEffects)

                val mediaItem = MediaItem.fromUri(Uri.fromFile(File(inputPath)))
                val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                    .setEffects(effects)
                    .build()

                val transformer = Transformer.Builder(context)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            Handler(Looper.getMainLooper()).post {
                                result.success(outputPath)
                            }
                        }

                        // FIX: Precise error reporting sent back to Flutter
                        override fun onError(composition: Composition, exportResult: ExportResult, exception: ExportException) {
                            Handler(Looper.getMainLooper()).post {
                                val errorCode = when (exception.errorCode) {
                                    ExportException.ERROR_CODE_IO_UNSPECIFIED -> "IO_LOCK_ERROR"
                                    ExportException.ERROR_CODE_DECODING_FAILED -> "CODEC_FAIL"
                                    else -> "TRANSFORM_ERROR"
                                }
                                result.error(errorCode, exception.message, null)
                            }
                        }
                    })
                    .build()

                transformer.start(editedMediaItem, outputPath)

            } else {
                result.notImplemented()
            }
        }
    }
}