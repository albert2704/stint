import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var filesChannel: FlutterMethodChannel?
  private var menuBar: StintMenuBar?
  private var music: StintMusic?
  private var blocker: StintBlocker?

  override func close() {
    menuBar?.windowWillClose()
    orderOut(nil)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 480, height: 758))
    self.contentMinSize = NSSize(width: 420, height: 600)
    self.center()
    self.title = "Stint"
    self.isReleasedWhenClosed = false

    RegisterGeneratedPlugins(registry: flutterViewController)
    filesChannel = FlutterMethodChannel(name: "stint/files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    filesChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "closed", message: "Window closed.", details: nil))
        return
      }
      do {
        switch call.method {
        case "dataDirectory":
          result(try self.dataDirectory().path)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch { result(FlutterError(code: "storage_failed", message: error.localizedDescription, details: nil)) }
    }

    menuBar = StintMenuBar(window: self, messenger: flutterViewController.engine.binaryMessenger)
    music = StintMusic(window: self, messenger: flutterViewController.engine.binaryMessenger)
    blocker = StintBlocker(window: self, messenger: flutterViewController.engine.binaryMessenger)
    music?.youTubeViewChanged = { [weak self] view in
      self?.menuBar?.setYouTubeView(view)
    }
    music?.showYouTubePlayer = { [weak self] in
      self?.menuBar?.showYouTubePlayer()
    }
    menuBar?.youTubeVisibilityChanged = { [weak self] visible in
      self?.music?.youTubeVisibilityChanged(visible)
    }
    super.awakeFromNib()
  }

  private func dataDirectory() throws -> URL {
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let directory = support.appendingPathComponent("Stint", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
