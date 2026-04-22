import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    guard let controller = controller else { return }

    let channel = FlutterMethodChannel(
      name: "com.armelchao.notesApp/clipboard",
      binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      if call.method == "getImageData" {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) {
          result(["data": FlutterStandardTypedData(bytes: data), "ext": "png"])
          return
        }
        if let tiffData = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiffData),
           let pngData = rep.representation(using: .png, properties: [:]) {
          result(["data": FlutterStandardTypedData(bytes: pngData), "ext": "png"])
          return
        }
        if let data = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
          result(["data": FlutterStandardTypedData(bytes: data), "ext": "jpg"])
          return
        }
        if let data = pb.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")) {
          result(["data": FlutterStandardTypedData(bytes: data), "ext": "gif"])
          return
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
