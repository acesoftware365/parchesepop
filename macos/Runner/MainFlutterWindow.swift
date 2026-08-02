import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let targetWidth = min(1180, visibleFrame.width * 0.92)
    let targetHeight = min(820, visibleFrame.height * 0.90)
    let windowFrame = NSRect(
      x: visibleFrame.midX - targetWidth / 2,
      y: visibleFrame.midY - targetHeight / 2,
      width: targetWidth,
      height: targetHeight
    )
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 760, height: 620)
    self.title = "Parchís Pop"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
