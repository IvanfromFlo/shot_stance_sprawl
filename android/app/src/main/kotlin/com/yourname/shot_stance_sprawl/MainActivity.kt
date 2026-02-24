package com.yourname.shot_stance_sprawl

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
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

                // Load Flutter asset safely
                val loader = io.flutter.FlutterInjector.instance().flutterLoader()
                val key = loader.getLookupKeyForAsset(assetPath)

                val bitmap: Bitmap = try {
                    BitmapFactory.decodeStream(context.assets.open(key))
                } catch (e: Exception) {
                    result.error("ASSET_ERROR", "Could not load watermark asset", null)
                    return@setMethodCallHandler
                }

                val outputPath = File(context.cacheDir, "watermarked_${System.currentTimeMillis()}.mp4").absolutePath

                // Create a Media3 Overlay using the Bitmap
                val overlay = object : BitmapOverlay() {
                    override fun getBitmap(presentationTimeUs: Long): Bitmap {
                        return bitmap
                    }
                }

                val overlayEffect = OverlayEffect(ImmutableList.of(overlay))
                val effects = Effects(ImmutableList.empty(), ImmutableList.of(overlayEffect))

                val mediaItem = MediaItem.fromUri(Uri.fromFile(File(inputPath)))
                val editedMediaItem = EditedMediaItem.Builder(mediaItem)
                    .setEffects(effects)
                    .build()

                // Execute the transformation asynchronously
                val transformer = Transformer.Builder(context)
                    .addListener(object : Transformer.Listener {
                        override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                            Handler(Looper.getMainLooper()).post {
                                result.success(outputPath)
                            }
                        }

                        override fun onError(composition: Composition, exportResult: ExportResult, exception: ExportException) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("TRANSFORM_ERROR", exception.message, null)
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