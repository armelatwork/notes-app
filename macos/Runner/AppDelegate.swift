import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var menuObservation: NSKeyValueObservation?
  private var isSettingMenu = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let icon = NSImage(named: "AppIcon") {
      NSApp.applicationIconImage = icon
    }

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

    // Let Flutter finish its own initialisation before we set our menu.
    super.applicationDidFinishLaunching(notification)
    setupAppMenu()

    // Flutter resets NSApp.mainMenu on every widget-tree rebuild (login /
    // logout). Observe the property and reapply our menu whenever it changes
    // to something we did not set ourselves.
    menuObservation = NSApp.observe(\.mainMenu, options: [.new]) { [weak self] _, change in
      guard let self = self, !self.isSettingMenu else { return }
      if change.newValue??.item(withTitle: "My Notes") == nil {
        DispatchQueue.main.async { self.setupAppMenu() }
      }
    }
  }

  private func setupAppMenu() {
    isSettingMenu = true
    defer { isSettingMenu = false }

    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu()
    appMenuItem.submenu = appMenu
    appMenu.addItem(withTitle: "About My Notes",
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                    keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide My Notes",
                    action: #selector(NSApplication.hide(_:)),
                    keyEquivalent: "h")
    let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(withTitle: "Show All",
                    action: #selector(NSApplication.unhideAllApplications(_:)),
                    keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit My Notes",
                    action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q")
    NSApp.mainMenu = mainMenu
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
