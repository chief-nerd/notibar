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
      createItem(id: id, title: title, iconName: args?["iconName"] as? String, tooltip: args?["tooltip"] as? String)
      result(nil)

    case "update":
      guard let id = args?["id"] as? String,
            let title = args?["title"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "id and title required", details: nil))
        return
      }
      updateItem(id: id, title: title, iconName: args?["iconName"] as? String, tooltip: args?["tooltip"] as? String)
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

  private func createItem(id: String, title: String, iconName: String? = nil, tooltip: String? = nil) {
    NSLog("[MultiStatusItem] createItem id=\(id) title=\(title) iconName=\(iconName ?? "nil")")
    if statusItems[id] != nil { return }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(onStatusItemClick(_:))
    // Store the id in the button's identifier for lookup
    item.button?.identifier = NSUserInterfaceItemIdentifier(id)

    statusItems[id] = item
    itemOrder.append(id)
    
    applyItemConfig(id: id, title: title, iconName: iconName, tooltip: tooltip)
  }

  private func updateItem(id: String, title: String, iconName: String? = nil, tooltip: String? = nil) {
    guard statusItems[id] != nil else {
      // Auto-create if it doesn't exist
      createItem(id: id, title: title, iconName: iconName, tooltip: tooltip)
      return
    }
    applyItemConfig(id: id, title: title, iconName: iconName, tooltip: tooltip)
  }

  // MARK: - Display style feature flag
  // Switch between Option A (native icon + title) and Option B (icon with badge overlay).
  private static let useOptionB = false

  private func applyItemConfig(id: String, title: String, iconName: String?, tooltip: String? = nil) {
    guard let item = statusItems[id] else { return }

    item.button?.toolTip = tooltip

    let displayTitle = title

    let isNumeric = Int(title) != nil || title == "99+"

    if let iconName = iconName, !iconName.isEmpty, isNumeric || title == "+", Self.useOptionB,
       #available(macOS 11.0, *),
       let badgedImage = makeBadgedImage(iconName: iconName, badgeText: displayTitle) {
      // Option B: full-size icon with badge overlay — narrowest possible
      item.button?.image = badgedImage
      item.button?.title = ""
      item.button?.imagePosition = .imageOnly
      return
    }

    // Option A: native icon + number title (also used for non-numeric labels like "–", "⚠", gear)
    if let iconName = iconName, !iconName.isEmpty {
      var image: NSImage?
      if #available(macOS 11.0, *) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
          .withSymbolConfiguration(config)
      }
      if image == nil {
        image = NSImage(named: iconName)
        image?.size = NSSize(width: 14, height: 14)
      }

      if let src = image {
        // 1pt left margin only — right side handled by imageHugsTitle
        let margin: CGFloat = 1.0
        let padded = NSImage(size: NSSize(width: src.size.width + margin, height: src.size.height), flipped: false) { _ in
          src.draw(in: NSRect(x: margin, y: 0, width: src.size.width, height: src.size.height))
          return true
        }
        padded.isTemplate = true
        item.button?.image = padded
        item.button?.imageHugsTitle = true   // removes built-in gap between image and title
        item.button?.imagePosition = displayTitle.isEmpty ? .imageOnly : .imageLeft
        // Trailing thin space adds right margin after the number
        item.button?.title = displayTitle.isEmpty ? "" : displayTitle + "\u{2009}"
      } else {
        item.button?.image = nil
        item.button?.title = displayTitle.isEmpty ? "⚙" : displayTitle
      }
    } else {
      item.button?.image = nil
      item.button?.title = displayTitle.isEmpty ? "?" : displayTitle
    }
  }

  /// Option B: SF Symbol fills most of the canvas; a small filled pill badge sits
  /// in the bottom-right corner with white text. Width = icon width only (~18pt).
  @available(macOS 11.0, *)
  private func makeBadgedImage(iconName: String, badgeText: String) -> NSImage? {
    // Icon configuration — full menu bar height, medium weight for clarity
    let symConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
    guard let sfImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symConfig) else { return nil }

    // Number text — same color as icon, no background
    let numFont = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .bold)
    let measureAttrs: [NSAttributedString.Key: Any] = [.font: numFont]
    let textSize = NSAttributedString(string: badgeText, attributes: measureAttrs).size()

    let iconPillGap: CGFloat = 1.0
    let iconSize = sfImage.size
    let margin: CGFloat = 2.0
    // Canvas = margin + icon + gap + text + margin
    let canvasW = margin + iconSize.width + iconPillGap + textSize.width + margin
    let canvasH: CGFloat = 16.0

    let image = NSImage(size: NSSize(width: canvasW, height: canvasH), flipped: false) { _ in
      let isDark = NSAppearance.current.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      let fgColor: NSColor = isDark ? .white : .black

      // 1. Draw number, baseline-aligned with icon bottom
      let numX = margin + iconSize.width + iconPillGap
      let numY: CGFloat = 0
      let textAttrs: [NSAttributedString.Key: Any] = [
        .font: numFont,
        .foregroundColor: fgColor,
      ]
      NSAttributedString(string: badgeText, attributes: textAttrs).draw(at: NSPoint(x: numX, y: numY))

      // 2. Draw SF Symbol, pinned to top of canvas
      let iconY = canvasH - iconSize.height
      let iconRect = NSRect(x: margin, y: iconY, width: iconSize.width, height: iconSize.height)
      let tintedIcon = NSImage(size: iconSize, flipped: false) { _ in
        fgColor.setFill()
        NSRect(origin: .zero, size: iconSize).fill()
        sfImage.draw(in: NSRect(origin: .zero, size: iconSize), from: .zero,
                     operation: .destinationIn, fraction: 1.0)
        return true
      }
      tintedIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)

      return true
    }

    image.isTemplate = false
    return image
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
