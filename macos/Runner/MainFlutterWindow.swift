import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register our custom multi-status-item plugin
    NSLog("[MainFlutterWindow] About to register MultiStatusItemPlugin")
    let registrar = flutterViewController.registrar(forPlugin: "MultiStatusItemPlugin")
    MultiStatusItemPlugin.register(with: registrar)
    NSLog("[MainFlutterWindow] MultiStatusItemPlugin registered")

    super.awakeFromNib()
  }
}
