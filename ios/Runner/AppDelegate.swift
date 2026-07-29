import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var backgroundMusic: AVAudioPlayer?
  private var effectPlayer: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let controller = window?.rootViewController as! FlutterViewController
    let soundChannel = FlutterMethodChannel(
      name: "com.liisgo.parchesepop/sounds",
      binaryMessenger: controller.binaryMessenger
    )
    soundChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "Audio unavailable", details: nil))
        return
      }
      switch call.method {
      case "setMusicEnabled":
        let arguments = call.arguments as? [String: Any]
        if arguments?["enabled"] as? Bool == true {
          self.playBackgroundMusic()
        } else {
          self.backgroundMusic?.stop()
        }
        result(nil)
      case "playEffect":
        let arguments = call.arguments as? [String: Any]
        self.playEffect(named: arguments?["asset"] as? String)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func soundURL(named name: String) -> URL? {
    // Flutter packages application assets inside App.framework, rather than
    // the main Runner bundle. Looking in the main bundle made every request
    // silently fail on a physical iPhone.
    guard let frameworksPath = Bundle.main.privateFrameworksPath,
          let appFramework = Bundle(path: "\(frameworksPath)/App.framework") else {
      return nil
    }
    return appFramework.url(
      forResource: name,
      withExtension: nil,
      subdirectory: "flutter_assets/assets/sounds"
    )
  }

  private func prepareAudioSession() {
    // `.playback` keeps game sounds audible even when the hardware mute
    // switch is on, which is the expected behavior for an interactive game.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try? AVAudioSession.sharedInstance().setActive(true)
  }

  private func playBackgroundMusic() {
    guard let url = soundURL(named: "background_music.wav") else { return }
    prepareAudioSession()
    backgroundMusic = try? AVAudioPlayer(contentsOf: url)
    backgroundMusic?.numberOfLoops = -1
    backgroundMusic?.volume = 0.42
    backgroundMusic?.play()
  }

  private func playEffect(named name: String?) {
    guard let name, let url = soundURL(named: name) else { return }
    prepareAudioSession()
    effectPlayer = try? AVAudioPlayer(contentsOf: url)
    effectPlayer?.volume = 0.82
    effectPlayer?.play()
  }
}
