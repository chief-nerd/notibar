import Cocoa
import FlutterMacOS

/// Manages multiple NSStatusItems in the macOS menu bar, each with its own menu.
/// Communicates with Dart via a FlutterMethodChannel.
class MultiStatusItemPlugin: NSObject, FlutterPlugin {
  static let channelName = "notibar/multi_status_item"

  private let channel: FlutterMethodChannel
  /// Ordered list of item IDs — rightmost in the bar appears first in this list.
  private var itemOrder: [String] = []
  private var statusItems: [String: NSStatusItem] = [:]
  private var menus: [String: NSMenu] = [:]
  /// Callbacks keyed by "\(itemId):\(menuItemIndex)"
  private var menuActions: [String: () -> Void] = [:]

  public static func register(with registrar: FlutterPluginRegistrar) {
    NSLog("[MultiStatusItem] register() called")
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger
    )
    let instance = MultiStatusItemPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    NSLog("[MultiStatusItem] register() done, channel: \\(channelName)")
  }

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  // MARK: - Method call dispatch

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    // Log method name with compact summary (avoid dumping full item arrays)
    if call.method == "setMenu", let items = args?["items"] as? [[String: Any]] {
      NSLog("[MultiStatusItem] handle method: setMenu id=\(args?["id"] ?? "?") items=\(items.count)")
    } else {
      NSLog("[MultiStatusItem] handle method: \(call.method) id=\(args?["id"] ?? "?")")
    }

    switch call.method {
    case "create":
      guard let id = args?["id"] as? String,
            let title = args?["title"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "id and title required", details: nil))
        return
      }
      createItem(id: id, title: title, iconName: args?["iconName"] as? String)
      result(nil)

    case "update":
      guard let id = args?["id"] as? String,
            let title = args?["title"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "id and title required", details: nil))
        return
      }
      updateItem(id: id, title: title, iconName: args?["iconName"] as? String)
      result(nil)

    case "remove":
      guard let id = args?["id"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "id required", details: nil))
        return
      }
      removeItem(id: id)
      result(nil)

    case "setMenu":
      guard let id = args?["id"] as? String,
            let items = args?["items"] as? [[String: Any]] else {
        result(FlutterError(code: "INVALID_ARGS", message: "id and items required", details: nil))
        return
      }
      setMenu(id: id, items: items)
      result(nil)

    case "removeAll":
      removeAll()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Status item management

  private func createItem(id: String, title: String, iconName: String? = nil) {
    NSLog("[MultiStatusItem] createItem id=\(id) title=\(title) iconName=\(iconName ?? "nil")")
    if statusItems[id] != nil { return }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(onStatusItemClick(_:))
    // Store the id in the button's identifier for lookup
    item.button?.identifier = NSUserInterfaceItemIdentifier(id)

    statusItems[id] = item
    itemOrder.append(id)
    
    applyItemConfig(id: id, title: title, iconName: iconName)
  }

  private func updateItem(id: String, title: String, iconName: String? = nil) {
    guard statusItems[id] != nil else {
      // Auto-create if it doesn't exist
      createItem(id: id, title: title, iconName: iconName)
      return
    }
    applyItemConfig(id: id, title: title, iconName: iconName)
  }

  private func applyItemConfig(id: String, title: String, iconName: String?) {
    guard let item = statusItems[id] else { return }
    
    if let iconName = iconName, !iconName.isEmpty {
      var image: NSImage?
      
      // Try SF Symbol first (macOS 11+), then named image asset
      if #available(macOS 11.0, *) {
        image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
      }
      if image == nil {
        image = NSImage(named: iconName)
      }
      
      if let image = image {
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        item.button?.image = image
        item.button?.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        item.button?.title = title
      } else {
        // Fallback: use title only (ensures item is visible)
        item.button?.image = nil
        item.button?.title = title.isEmpty ? "⚙" : title
      }
    } else {
      item.button?.image = nil
      item.button?.title = title.isEmpty ? "?" : title
    }
  }

  private func removeItem(id: String) {
    guard let item = statusItems[id] else { return }
    NSStatusBar.system.removeStatusItem(item)
    statusItems.removeValue(forKey: id)
    itemOrder.removeAll { $0 == id }
    menus.removeValue(forKey: id)
    // Clean up related menu actions
    menuActions = menuActions.filter { !$0.key.hasPrefix("\(id):") }
  }

  private func removeAll() {
    for (_, item) in statusItems {
      NSStatusBar.system.removeStatusItem(item)
    }
    statusItems.removeAll()
    itemOrder.removeAll()
    menus.removeAll()
    menuActions.removeAll()
  }

  private func setMenu(id: String, items: [[String: Any]]) {
    let menu = NSMenu()
    // Clean up old actions for this item
    menuActions = menuActions.filter { !$0.key.hasPrefix("\(id):") }

    for (index, itemData) in items.enumerated() {
      let menuItem = buildMenuItem(id: id, index: index, data: itemData)
      menu.addItem(menuItem)

      // Handle submenu children
      if let children = itemData["children"] as? [[String: Any]], !children.isEmpty {
        let submenu = NSMenu()
        for (childIndex, childData) in children.enumerated() {
          // Use a composite index so callbacks route correctly: parentIndex * 1000 + childIndex
          let flatIndex = index * 1000 + childIndex
          let childItem = buildMenuItem(id: id, index: flatIndex, data: childData)
          submenu.addItem(childItem)
        }
        menuItem.submenu = submenu
      }
    }

    menus[id] = menu
    statusItems[id]?.menu = menu
  }

  /// Builds a single NSMenuItem from the data dictionary, wiring up attributed titles and callbacks.
  private func buildMenuItem(id: String, index: Int, data: [String: Any]) -> NSMenuItem {
    let type = data["type"] as? String ?? "item"
    if type == "separator" {
      return NSMenuItem.separator()
    }

    let label = data["label"] as? String ?? ""
    let subtitle = data["subtitle"] as? String
    let enabled = data["enabled"] as? Bool ?? true
    let hasCallback = data["hasCallback"] as? Bool ?? false

    let menuItem = NSMenuItem(title: label, action: nil, keyEquivalent: "")
    menuItem.isEnabled = enabled

    // Build attributed title for rich two-line display
    if let subtitle = subtitle, !subtitle.isEmpty {
      let titleFont = NSFont.menuFont(ofSize: 13)
      let subtitleFont = NSFont.menuFont(ofSize: 11)
      let titleColor: NSColor = enabled ? .labelColor : .secondaryLabelColor
      let subtitleColor: NSColor = .secondaryLabelColor

      let attrStr = NSMutableAttributedString()
      attrStr.append(NSAttributedString(string: label, attributes: [
        .font: titleFont,
        .foregroundColor: titleColor,
      ]))
      attrStr.append(NSAttributedString(string: "\n", attributes: [
        .font: NSFont.menuFont(ofSize: 2),
      ]))
      attrStr.append(NSAttributedString(string: subtitle, attributes: [
        .font: subtitleFont,
        .foregroundColor: subtitleColor,
      ]))
      menuItem.attributedTitle = attrStr
    }

    if enabled && hasCallback {
      let actionKey = "\(id):\(index)"
      menuItem.target = self
      menuItem.action = #selector(onMenuItemClick(_:))
      menuItem.tag = index
      menuItem.representedObject = id as NSString

      menuActions[actionKey] = { [weak self] in
        self?.channel.invokeMethod("onMenuItemClick", arguments: [
          "itemId": id,
          "menuIndex": index,
        ])
      }
    }

    return menuItem
  }

  // MARK: - Click handlers

  @objc private func onStatusItemClick(_ sender: NSStatusBarButton) {
    guard let id = sender.identifier?.rawValue else { return }
    // When there's a menu, NSStatusItem shows it automatically.
    // This handler is for clicks without a menu (fallback).
    channel.invokeMethod("onStatusItemClick", arguments: ["itemId": id])
  }

  @objc private func onMenuItemClick(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    let actionKey = "\(id):\(sender.tag)"
    menuActions[actionKey]?()
  }
}
