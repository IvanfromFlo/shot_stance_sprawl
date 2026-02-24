import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
      
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.yourname.shot_stance_sprawl/watermark",
                                      binaryMessenger: controller.binaryMessenger)
    
    channel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "addWatermark" {
            guard let args = call.arguments as? [String: Any],
                  let videoPath = args["videoPath"] as? String,
                  let assetPath = args["watermarkAsset"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
                return
            }
            
            // Resolve the Flutter asset to a usable iOS Path
            let flutterKey = controller.lookupKey(forAsset: assetPath)
            guard let imagePath = Bundle.main.path(forResource: flutterKey, ofType: nil),
                  let watermarkImage = UIImage(contentsOfFile: imagePath) else {
                result(FlutterError(code: "ASSET_ERROR", message: "Could not load watermark", details: nil))
                return
            }
            
            self?.applyWatermark(videoPath: videoPath, watermarkImage: watermarkImage, result: result)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
    
  private func applyWatermark(videoPath: String, watermarkImage: UIImage, result: @escaping FlutterResult) {
      let videoURL = URL(fileURLWithPath: videoPath)
      let asset = AVURLAsset(url: videoURL)
      
      let composition = AVMutableVideoComposition(propertiesOf: asset)
      
      let watermarkLayer = CALayer()
      watermarkLayer.contents = watermarkImage.cgImage
      
      // Calculate scaling & placement (Bottom Right logic)
      let videoSize = composition.renderSize
      let watermarkWidth = videoSize.width * 0.15
      let watermarkHeight = watermarkWidth * (watermarkImage.size.height / watermarkImage.size.width)
      
      // Note: AVFoundation origin (0,0) is at the bottom-left of the screen
      watermarkLayer.frame = CGRect(x: videoSize.width - watermarkWidth - 20,
                                    y: 20,
                                    width: watermarkWidth,
                                    height: watermarkHeight)
      watermarkLayer.opacity = 0.85
      
      let parentLayer = CALayer()
      let videoLayer = CALayer()
      parentLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
      videoLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
      
      parentLayer.addSublayer(videoLayer)
      parentLayer.addSublayer(watermarkLayer)
      
      composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
      
      let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("watermarked_\(UUID().uuidString).mp4")
      
      guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
          result(FlutterError(code: "EXPORT_ERROR", message: "Cannot create export session", details: nil))
          return
      }
      
      exportSession.outputURL = outputURL
      exportSession.outputFileType = .mp4
      exportSession.videoComposition = composition
      
      exportSession.exportAsynchronously {
          DispatchQueue.main.async {
              switch exportSession.status {
              case .completed:
                  result(outputURL.path)
              case .failed, .cancelled:
                  // Print debug info, but fail gracefully
                  result(FlutterError(code: "EXPORT_FAILED", message: exportSession.error?.localizedDescription, details: nil))
              default:
                  result(FlutterError(code: "UNKNOWN", message: "Unknown export status", details: nil))
              }
          }
      }
  }
}