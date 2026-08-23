import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    super.awakeFromNib()
    // Always honor the product's portrait startup workspace. AppKit can
    // otherwise restore a previously maximized frame before Flutter paints.
    self.isRestorable = false
    self.setFrameAutosaveName("")
    let flutterViewController = FlutterViewController()
    let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    // Match the portrait workspace shown by the in-app size badge. Using a
    // content rect (rather than a frame rect) keeps the Flutter viewport at
    // exactly 760 × 1143 points; the title bar is added by AppKit.
    let targetContentSize = NSSize(width: 760, height: 1143)
    let frameSize = self.frameRect(
      forContentRect: NSRect(origin: .zero, size: targetContentSize)
    ).size
    let windowFrame = NSRect(
      x: visibleFrame.midX - frameSize.width / 2,
      y: visibleFrame.midY - frameSize.height / 2,
      width: frameSize.width,
      height: frameSize.height
    )
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true, animate: false)
    if self.isZoomed {
      self.zoom(nil)
    }
    self.setFrame(windowFrame, display: true, animate: false)
    self.minSize = NSSize(width: 760, height: 620)
    self.title = "Parchís Pop"

    RegisterGeneratedPlugins(registry: flutterViewController)

    // AppKit may restore the previous frame after awakeFromNib. Reapply the
    // requested default on the next run-loop turn so a prior maximized window
    // cannot override the 760 × 1143 startup workspace.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if self.isZoomed {
        self.zoom(nil)
      }
      self.setFrame(windowFrame, display: true, animate: false)
    }
  }
}
