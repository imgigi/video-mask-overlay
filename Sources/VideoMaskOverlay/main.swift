import AppKit
import CoreGraphics
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayController!
    private var enabledItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayController()
        buildStatusMenu()
        overlayController.show()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    private func buildStatusMenu() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }
        statusItem.button?.title = ""
        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.toolTip = "视频遮罩"

        let menu = NSMenu()

        enabledItem = NSMenuItem(title: "启用遮罩", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = .on
        menu.addItem(enabledItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "显示层级", action: nil, keyEquivalent: ""))
        OverlayLevelPreset.allCases.forEach { addLevelItem(to: menu, preset: $0) }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "目标窗口", action: nil, keyEquivalent: ""))
        let manualItem = NSMenuItem(title: "手动范围", action: #selector(selectManualTarget), keyEquivalent: "")
        manualItem.target = self
        manualItem.state = overlayController.selectedWindowID == nil ? .on : .off
        menu.addItem(manualItem)

        let windows = WindowCatalog.visibleWindows()
        if windows.isEmpty {
            let emptyItem = NSMenuItem(title: "未发现可选窗口", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            windows.prefix(25).forEach { addWindowItem(to: menu, window: $0) }
        }

        let refreshWindowItem = NSMenuItem(title: "刷新窗口列表", action: #selector(rebuildMenu), keyEquivalent: "")
        refreshWindowItem.target = self
        menu.addItem(refreshWindowItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "颜色", action: nil, keyEquivalent: ""))
        addColorItem(to: menu, title: "白色", color: .white)
        addColorItem(to: menu, title: "黑色", color: .black)
        addTextFieldItem(to: menu, title: "Hex", value: hexString(for: overlayController.color), tag: TextFieldTag.hexColor.rawValue)

        menu.addItem(.separator())

        addSliderItem(to: menu, title: "透明度", value: sliderValue(forOpacity: overlayController.opacity), tag: SliderTag.opacity.rawValue)
        addTextFieldItem(to: menu, title: "透明度", value: "\(Int((overlayController.opacity * 100).rounded()))", tag: TextFieldTag.opacity.rawValue)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "图片遮罩", action: nil, keyEquivalent: ""))
        let chooseImageItem = NSMenuItem(title: overlayController.hasImageMask ? "更换图片..." : "选择图片...", action: #selector(chooseImageMask), keyEquivalent: "")
        chooseImageItem.target = self
        menu.addItem(chooseImageItem)

        menu.addItem(.separator())
        let rangeTitle = overlayController.selectedWindowID == nil ? "范围" : "范围 - 已跟随目标窗口"
        menu.addItem(NSMenuItem(title: rangeTitle, action: nil, keyEquivalent: ""))

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeStatusIcon() -> NSImage {
        if let image = NSImage(systemSymbolName: "rectangle.inset.filled", accessibilityDescription: "视频遮罩") {
            image.isTemplate = true
            return image
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.labelColor.setStroke()
        let outer = NSBezierPath(roundedRect: NSRect(x: 2, y: 3, width: 14, height: 12), xRadius: 2, yRadius: 2)
        outer.lineWidth = 1.6
        outer.stroke()
        NSColor.labelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(rect: NSRect(x: 5, y: 6, width: 8, height: 6)).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    @discardableResult
    private func addSliderItem(to menu: NSMenu, title: String, value: Double, tag: Int, isEnabled: Bool = true) -> NSSlider {
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 40))
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 12, y: 12, width: 70, height: 18)
        label.isEnabled = isEnabled
        sliderView.addSubview(label)

        let slider = NSSlider(value: value, minValue: 0.0, maxValue: 1.0, target: self, action: #selector(sliderChanged(_:)))
        slider.tag = tag
        slider.isEnabled = isEnabled
        slider.frame = NSRect(x: 88, y: 8, width: 148, height: 24)
        sliderView.addSubview(slider)

        let item = NSMenuItem()
        item.view = sliderView
        menu.addItem(item)
        return slider
    }

    private func addColorItem(to menu: NSMenu, title: String, color: NSColor) {
        let item = NSMenuItem(title: title, action: #selector(colorSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = color
        item.state = colorsMatch(overlayController.color, color) ? .on : .off
        menu.addItem(item)
    }

    private func addTextFieldItem(to menu: NSMenu, title: String, value: String, tag: Int) {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 38))
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 12, y: 10, width: 70, height: 18)
        row.addSubview(label)

        let field = NSTextField(string: value)
        field.frame = NSRect(x: 88, y: 7, width: 148, height: 24)
        field.tag = tag
        field.target = self
        field.action = #selector(textFieldSubmitted(_:))
        field.delegate = self
        row.addSubview(field)

        let item = NSMenuItem()
        item.view = row
        menu.addItem(item)
    }

    private func addLevelItem(to menu: NSMenu, preset: OverlayLevelPreset) {
        let item = NSMenuItem(title: preset.title, action: #selector(levelSelected(_:)), keyEquivalent: "")
        item.target = self
        item.tag = preset.rawValue
        item.state = overlayController.levelPreset == preset ? .on : .off
        menu.addItem(item)
    }

    private func addWindowItem(to menu: NSMenu, window: WindowInfo) {
        let item = NSMenuItem(title: window.menuTitle, action: #selector(windowSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = NSNumber(value: window.id)
        item.state = overlayController.selectedWindowID == window.id ? .on : .off
        menu.addItem(item)
    }

    @objc private func toggleEnabled() {
        overlayController.isEnabled.toggle()
        enabledItem.state = overlayController.isEnabled ? .on : .off
    }

    @objc private func colorSelected(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? NSColor else { return }
        overlayController.clearImageMask()
        overlayController.color = color

        sender.menu?.items.forEach { item in
            if item.representedObject is NSColor {
                item.state = item === sender ? .on : .off
            }
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        switch SliderTag(rawValue: sender.tag) {
        case .opacity:
            overlayController.opacity = opacity(forSliderValue: sender.doubleValue)
        case .none:
            break
        }
    }

    @objc private func textFieldSubmitted(_ sender: NSTextField) {
        applyTextFieldValue(sender)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        applyTextFieldValue(field)
    }

    private func applyTextFieldValue(_ field: NSTextField) {
        switch TextFieldTag(rawValue: field.tag) {
        case .hexColor:
            if let color = colorFromHexInput(field.stringValue) {
                overlayController.clearImageMask()
                overlayController.color = color
                field.stringValue = hexString(for: color)
            } else {
                field.stringValue = hexString(for: overlayController.color)
            }
        case .opacity:
            let value = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? overlayController.opacity * 100
            overlayController.opacity = min(max(value / 100, 0), 1)
            field.stringValue = "\(Int((overlayController.opacity * 100).rounded()))"
        case .none:
            break
        }
    }

    @objc private func levelSelected(_ sender: NSMenuItem) {
        guard let preset = OverlayLevelPreset(rawValue: sender.tag) else { return }
        overlayController.levelPreset = preset
        buildStatusMenu()
    }

    @objc private func selectManualTarget() {
        overlayController.selectedWindowID = nil
        buildStatusMenu()
    }

    @objc private func windowSelected(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        overlayController.levelPreset = .normal
        overlayController.selectedWindowID = CGWindowID(number.uint32Value)
        buildStatusMenu()
    }

    @objc private func chooseImageMask() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        activateAppForPrompt()

        guard panel.runModal() == .OK, let url = panel.url else { return }
        overlayController.loadImageMask(from: url)
        buildStatusMenu()
    }

    @objc private func screenParametersChanged() {
        overlayController.refreshScreens()
    }

    @objc private func activeSpaceChanged() {
        overlayController.recoverAfterSpaceChange()
    }

    @objc private func rebuildMenu() {
        buildStatusMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func opacity(forSliderValue sliderValue: Double) -> Double {
        let value = min(max(sliderValue, 0), 1)
        if value <= 0.6 {
            return value / 0.6 * 0.8
        }

        return 0.8 + (value - 0.6) / 0.4 * 0.2
    }

    private func sliderValue(forOpacity opacity: Double) -> Double {
        let value = min(max(opacity, 0), 1)
        if value <= 0.8 {
            return value / 0.8 * 0.6
        }

        return 0.6 + (value - 0.8) / 0.2 * 0.4
    }

    private func colorFromHexInput(_ input: String) -> NSColor? {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }

        let red = (value >> 16) & 0xFF
        let green = (value >> 8) & 0xFF
        let blue = value & 0xFF
        return NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }

    private func rgbComponents(for color: NSColor) -> (red: Int, green: Int, blue: Int) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        return (
            Int((converted.redComponent * 255).rounded()),
            Int((converted.greenComponent * 255).rounded()),
            Int((converted.blueComponent * 255).rounded())
        )
    }

    private func hexString(for color: NSColor) -> String {
        let rgb = rgbComponents(for: color)
        return String(format: "#%02X%02X%02X", rgb.red, rgb.green, rgb.blue)
    }

    private func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = rgbComponents(for: lhs)
        let right = rgbComponents(for: rhs)
        return left.red == right.red && left.green == right.green && left.blue == right.blue
    }

    private func activateAppForPrompt() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private enum SliderTag: Int {
    case opacity = 1
}

private enum TextFieldTag: Int {
    case hexColor = 1
    case opacity
}

enum OverlayLevelPreset: Int, CaseIterable {
    case normal = 1
    case floating
    case strong

    var title: String {
        switch self {
        case .normal:
            "普通"
        case .floating:
            "置顶"
        case .strong:
            "强力置顶"
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .normal:
            .normal
        case .floating:
            .floating
        case .strong:
            .screenSaver
        }
    }
}

private struct WindowInfo {
    let id: CGWindowID
    let owner: String
    let title: String
    let quartzBounds: CGRect

    var menuTitle: String {
        let windowTitle = title.isEmpty ? "无标题窗口" : title
        return "\(owner) - \(windowTitle)".limited(to: 52)
    }
}

private enum WindowCatalog {
    static func visibleWindows() -> [WindowInfo] {
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap(makeWindowInfo)
    }

    static func window(id: CGWindowID) -> WindowInfo? {
        visibleWindows().first { $0.id == id }
    }

    static func frontmostWindowID() -> CGWindowID? {
        visibleWindows().first?.id
    }

    private static func makeWindowInfo(from dictionary: [String: Any]) -> WindowInfo? {
        guard
            let id = dictionary[kCGWindowNumber as String] as? CGWindowID,
            let owner = dictionary[kCGWindowOwnerName as String] as? String,
            let layer = dictionary[kCGWindowLayer as String] as? Int,
            let boundsValue = dictionary[kCGWindowBounds as String]
        else {
            return nil
        }

        let boundsDictionary = boundsValue as! CFDictionary

        if layer != 0 || owner == "VideoMaskOverlay" {
            return nil
        }

        if let pid = dictionary[kCGWindowOwnerPID as String] as? pid_t, pid == getpid() {
            return nil
        }

        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds), bounds.width >= 80, bounds.height >= 60 else {
            return nil
        }

        let alpha = dictionary[kCGWindowAlpha as String] as? Double ?? 1
        guard alpha > 0 else {
            return nil
        }

        let title = dictionary[kCGWindowName as String] as? String ?? ""
        return WindowInfo(id: id, owner: owner, title: title, quartzBounds: bounds)
    }
}

private extension String {
    func limited(to maximumLength: Int) -> String {
        if count <= maximumLength {
            return self
        }

        return String(prefix(maximumLength - 1)) + "..."
    }
}

private enum OverlayDragMode {
    case none
    case move
    case resize(left: Bool, right: Bool, bottom: Bool, top: Bool)
}

@MainActor
private final class OverlayEditView: NSView {
    var isEditing = false {
        didSet {
            updateEditChrome()
            resetCursorRects()
        }
    }

    var isEditingImageViewport = false {
        didSet {
            updateEditChrome()
            resetCursorRects()
        }
    }

    var frameDidChange: ((NSRect) -> Void)?
    var imageViewportDidPan: ((CGFloat, CGFloat) -> Void)?
    var imageViewportDidZoom: ((CGFloat) -> Void)?
    var imageViewportDidCrop: ((CGFloat, CGFloat, CGFloat, CGFloat) -> Void)?

    private let hitSize: CGFloat = 12
    private let minimumSize: CGFloat = 80
    private let opaqueImageLayer = CALayer()
    private let translucentImageLayer = CALayer()
    private var dragMode = OverlayDragMode.none
    private var imageDragMode = OverlayDragMode.none
    private var dragStartFrame = NSRect.zero
    private var dragStartMouse = NSPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupImageLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupImageLayer()
    }

    override func layout() {
        super.layout()
    }

    func setMaskColor(_ color: NSColor) {
        layer?.backgroundColor = color.cgColor
    }

    func setFilteredImage(_ image: CGImage?, opacity: Double) {
        opaqueImageLayer.isHidden = true
        translucentImageLayer.contentsGravity = .resizeAspectFill
        translucentImageLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        translucentImageLayer.frame = bounds
        translucentImageLayer.contents = image
        translucentImageLayer.opacity = Float(opacity)
        translucentImageLayer.mask = nil
        translucentImageLayer.isHidden = image == nil
    }

    func setImageMask(_ image: CGImage?, imageFrame: NSRect, transparentRect: NSRect, opacity: Double) {
        guard let image else {
            opaqueImageLayer.isHidden = true
            translucentImageLayer.isHidden = true
            opaqueImageLayer.mask = nil
            translucentImageLayer.mask = nil
            return
        }

        configureImageLayer(opaqueImageLayer, image: image, frame: imageFrame, opacity: 1)
        configureImageLayer(translucentImageLayer, image: image, frame: imageFrame, opacity: opacity)
        opaqueImageLayer.mask = inverseMask(for: transparentRect, inImageFrame: imageFrame)
        translucentImageLayer.mask = mask(for: transparentRect, inImageFrame: imageFrame)
        opaqueImageLayer.isHidden = false
        translucentImageLayer.isHidden = false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEditing || isEditingImageViewport else { return }

        if isEditingImageViewport {
            addCursorRect(bounds.insetBy(dx: hitSize, dy: hitSize), cursor: .openHand)
            addCursorRect(NSRect(x: 0, y: hitSize, width: hitSize, height: max(0, bounds.height - hitSize * 2)), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: bounds.maxX - hitSize, y: hitSize, width: hitSize, height: max(0, bounds.height - hitSize * 2)), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: hitSize, y: 0, width: max(0, bounds.width - hitSize * 2), height: hitSize), cursor: .resizeUpDown)
            addCursorRect(NSRect(x: hitSize, y: bounds.maxY - hitSize, width: max(0, bounds.width - hitSize * 2), height: hitSize), cursor: .resizeUpDown)
            addCursorRect(NSRect(x: 0, y: 0, width: hitSize, height: hitSize), cursor: .crosshair)
            addCursorRect(NSRect(x: bounds.maxX - hitSize, y: 0, width: hitSize, height: hitSize), cursor: .crosshair)
            addCursorRect(NSRect(x: 0, y: bounds.maxY - hitSize, width: hitSize, height: hitSize), cursor: .crosshair)
            addCursorRect(NSRect(x: bounds.maxX - hitSize, y: bounds.maxY - hitSize, width: hitSize, height: hitSize), cursor: .crosshair)
            return
        }

        addCursorRect(bounds.insetBy(dx: hitSize, dy: hitSize), cursor: .openHand)
        addCursorRect(NSRect(x: 0, y: hitSize, width: hitSize, height: max(0, bounds.height - hitSize * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.maxX - hitSize, y: hitSize, width: hitSize, height: max(0, bounds.height - hitSize * 2)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: hitSize, y: 0, width: max(0, bounds.width - hitSize * 2), height: hitSize), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: hitSize, y: bounds.maxY - hitSize, width: max(0, bounds.width - hitSize * 2), height: hitSize), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: 0, width: hitSize, height: hitSize), cursor: .crosshair)
        addCursorRect(NSRect(x: bounds.maxX - hitSize, y: 0, width: hitSize, height: hitSize), cursor: .crosshair)
        addCursorRect(NSRect(x: 0, y: bounds.maxY - hitSize, width: hitSize, height: hitSize), cursor: .crosshair)
        addCursorRect(NSRect(x: bounds.maxX - hitSize, y: bounds.maxY - hitSize, width: hitSize, height: hitSize), cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing || isEditingImageViewport, let window else {
            super.mouseDown(with: event)
            return
        }

        dragStartMouse = window.convertPoint(toScreen: event.locationInWindow)
        if isEditingImageViewport {
            imageDragMode = dragMode(for: event.locationInWindow)
            NSCursor.closedHand.set()
            return
        }

        dragMode = dragMode(for: event.locationInWindow)
        dragStartFrame = window.frame
        if case .move = dragMode {
            NSCursor.closedHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing || isEditingImageViewport, let window else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouse = window.convertPoint(toScreen: event.locationInWindow)
        let dx = currentMouse.x - dragStartMouse.x
        let dy = currentMouse.y - dragStartMouse.y
        if isEditingImageViewport {
            switch imageDragMode {
            case .none:
                break
            case .move:
                imageViewportDidPan?(dx, dy)
            case let .resize(left, right, bottom, top):
                if (left || right) && (bottom || top) {
                    let delta = abs(dx) > abs(dy) ? dx : dy
                    let direction: CGFloat = (left || bottom) ? -1 : 1
                    imageViewportDidZoom?(1 + direction * delta / max(80, min(bounds.width, bounds.height)))
                } else {
                    imageViewportDidCrop?(left ? dx : 0, right ? dx : 0, bottom ? dy : 0, top ? dy : 0)
                }
            }
            dragStartMouse = currentMouse
            return
        }

        let newFrame = adjustedFrame(from: dragStartFrame, dx: dx, dy: dy)
        window.setFrame(newFrame, display: true)
        frame = NSRect(origin: .zero, size: newFrame.size)
        frameDidChange?(newFrame)
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
        imageDragMode = .none
        if isEditing || isEditingImageViewport {
            NSCursor.openHand.set()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEditingImageViewport else {
            super.scrollWheel(with: event)
            return
        }

        let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.06 : 0.94
        imageViewportDidZoom?(factor)
    }

    private func dragMode(for windowPoint: NSPoint) -> OverlayDragMode {
        let point = convert(windowPoint, from: nil)
        let left = point.x <= hitSize
        let right = point.x >= bounds.maxX - hitSize
        let bottom = point.y <= hitSize
        let top = point.y >= bounds.maxY - hitSize

        if left || right || bottom || top {
            return .resize(left: left, right: right, bottom: bottom, top: top)
        }

        return .move
    }

    private func adjustedFrame(from frame: NSRect, dx: CGFloat, dy: CGFloat) -> NSRect {
        switch dragMode {
        case .none:
            return frame
        case .move:
            return NSRect(x: frame.minX + dx, y: frame.minY + dy, width: frame.width, height: frame.height)
        case let .resize(left, right, bottom, top):
            var rect = frame
            if left {
                let proposedWidth = frame.width - dx
                if proposedWidth >= minimumSize {
                    rect.origin.x = frame.origin.x + dx
                    rect.size.width = proposedWidth
                }
            }
            if right {
                rect.size.width = max(minimumSize, frame.width + dx)
            }
            if bottom {
                let proposedHeight = frame.height - dy
                if proposedHeight >= minimumSize {
                    rect.origin.y = frame.origin.y + dy
                    rect.size.height = proposedHeight
                }
            }
            if top {
                rect.size.height = max(minimumSize, frame.height + dy)
            }
            return rect
        }
    }

    private func updateEditChrome() {
        layer?.borderWidth = (isEditing || isEditingImageViewport) ? 3 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    private func setupImageLayer() {
        layer?.masksToBounds = true
        [opaqueImageLayer, translucentImageLayer].forEach { imageLayer in
            imageLayer.frame = bounds
            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.masksToBounds = true
            imageLayer.isHidden = true
            layer?.addSublayer(imageLayer)
        }
    }

    private func configureImageLayer(_ layer: CALayer, image: CGImage, frame: NSRect, opacity: Double) {
        layer.contentsGravity = .resizeAspectFill
        layer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.frame = frame
        layer.contents = image
        layer.opacity = Float(opacity)
    }

    private func mask(for transparentRect: NSRect, inImageFrame imageFrame: NSRect) -> CAShapeLayer {
        let localRect = transparentRect.offsetBy(dx: -imageFrame.minX, dy: -imageFrame.minY)
        let mask = CAShapeLayer()
        mask.frame = NSRect(origin: .zero, size: imageFrame.size)
        mask.path = CGPath(rect: localRect, transform: nil)
        return mask
    }

    private func inverseMask(for transparentRect: NSRect, inImageFrame imageFrame: NSRect) -> CAShapeLayer {
        let localRect = transparentRect.offsetBy(dx: -imageFrame.minX, dy: -imageFrame.minY)
        let path = CGMutablePath()
        path.addRect(NSRect(origin: .zero, size: imageFrame.size))
        path.addRect(localRect)

        let mask = CAShapeLayer()
        mask.frame = NSRect(origin: .zero, size: imageFrame.size)
        mask.fillRule = .evenOdd
        mask.path = path
        return mask
    }
}

@MainActor
final class OverlayController {
    var color: NSColor = .white {
        didSet { applyAppearance() }
    }

    var opacity: Double = 0.9 {
        didSet {
            opacity = min(max(opacity, 0), 1)
            applyAppearance()
        }
    }

    var isEnabled: Bool = true {
        didSet { updateVisibility(raiseTargetOverlay: true) }
    }

    var levelPreset: OverlayLevelPreset = .normal {
        didSet {
            updateLevels()
            updateVisibility(raiseTargetOverlay: true)
        }
    }

    var selectedWindowID: CGWindowID? {
        didSet {
            lastTargetFrame = nil
            imageGlobalFrame = nil
            missingTargetTicks = 0
            updateTrackingTimer()
            updateMouseMonitor()
            updateLevels()
            updateFrames()
            updateVisibility(raiseTargetOverlay: true)
        }
    }

    var hasImageMask: Bool {
        imageMask != nil
    }

    var widthRatio: Double = 0.7 {
        didSet {
            widthRatio = clampedSizeRatio(widthRatio)
            if !isApplyingManualDrag {
                updateFrames()
            }
        }
    }

    var heightRatio: Double = 0.7 {
        didSet {
            heightRatio = clampedSizeRatio(heightRatio)
            if !isApplyingManualDrag {
                updateFrames()
            }
        }
    }

    var leftRatio: Double = 0.15 {
        didSet {
            leftRatio = clampedPositionRatio(leftRatio)
            if !isApplyingManualDrag {
                updateFrames()
            }
        }
    }

    var topRatio: Double = 0.15 {
        didSet {
            topRatio = clampedPositionRatio(topRatio)
            if !isApplyingManualDrag {
                updateFrames()
            }
        }
    }

    private var panels: [NSPanel] = []
    private var trackingTimer: Timer?
    private var mouseMonitor: Any?
    private var lastTargetFrame: NSRect?
    private var missingTargetTicks = 0
    private let missingTargetLimit = 60
    private var isApplyingManualDrag = false
    private var imageMask: CGImage?
    private var imageGlobalFrame: NSRect?

    func show() {
        refreshScreens()
    }

    func refreshScreens() {
        panels.forEach { $0.close() }
        lastTargetFrame = nil
        missingTargetTicks = 0
        panels = NSScreen.screens.map(makePanel)
        applyAppearance()
        updateLevels()
        updateFrames()
        updateVisibility(raiseTargetOverlay: true)
    }

    func recoverAfterSpaceChange() {
        missingTargetTicks = 0
        scheduleSpaceRecovery(after: 0.05)
        scheduleSpaceRecovery(after: 0.2)
        scheduleSpaceRecovery(after: 0.6)
        scheduleSpaceRecovery(after: 1.0)
    }

    func loadImageMask(from url: URL) {
        guard let image = NSImage(contentsOf: url), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        imageMask = cgImage
        imageGlobalFrame = nil
        updateFrames()
        applyAppearance()
    }

    func clearImageMask() {
        imageMask = nil
        imageGlobalFrame = nil
        applyAppearance()
    }

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let rect = overlayRect(for: screen)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        let contentView = OverlayEditView(frame: NSRect(origin: .zero, size: rect.size))
        contentView.autoresizingMask = [.width, .height]
        contentView.frameDidChange = { [weak self, weak screen] newFrame in
            guard let self, let screen else { return }
            self.applyManualFrame(newFrame, on: screen)
        }
        contentView.imageViewportDidPan = { [weak self] dx, dy in
            self?.panImageViewport(dx: dx, dy: dy)
        }
        contentView.imageViewportDidZoom = { [weak self] factor in
            self?.zoomImageViewport(by: factor)
        }
        contentView.imageViewportDidCrop = { [weak self] left, right, bottom, top in
            self?.cropImageFrame(left: left, right: right, bottom: bottom, top: top)
        }
        panel.contentView = contentView
        configure(panel: panel)

        return panel
    }

    private func applyAppearance() {
        let maskColor = color.withAlphaComponent(opacity)
        panels.forEach { panel in
            guard let contentView = panel.contentView as? OverlayEditView else { return }
            if let imageMask {
                contentView.setMaskColor(.clear)
                let targetFrame = currentTargetFrame(for: panel)
                let imageFrame = imageGlobalFrame ?? defaultImageFrame(for: imageMask, targetFrame: targetFrame)
                imageGlobalFrame = imageFrame
                let panelFrame = targetFrame.union(imageFrame)
                if panel.frame != panelFrame {
                    panel.setFrame(panelFrame, display: true)
                    panel.contentView?.frame = NSRect(origin: .zero, size: panelFrame.size)
                }

                let localImageFrame = imageFrame.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
                let localTargetFrame = targetFrame.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
                contentView.setImageMask(imageMask, imageFrame: localImageFrame, transparentRect: localTargetFrame, opacity: opacity)
            } else {
                contentView.setMaskColor(maskColor)
                contentView.setImageMask(nil, imageFrame: .zero, transparentRect: .zero, opacity: opacity)
                contentView.setFilteredImage(nil, opacity: opacity)
            }
        }
    }

    private func updateLevels() {
        panels.forEach { $0.level = levelPreset.windowLevel }
    }

    private func configure(panel: NSPanel) {
        panel.ignoresMouseEvents = true
        (panel.contentView as? OverlayEditView)?.isEditing = false
        (panel.contentView as? OverlayEditView)?.isEditingImageViewport = false
    }

    private func updateFrames() {
        if let selectedWindowID {
            updateTargetWindowFrame(selectedWindowID)
            return
        }

        for panel in panels {
            guard let screen = panel.screen ?? NSScreen.main else { continue }
            let rect = overlayRect(for: screen)
            panel.setFrame(rect, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: rect.size)
        }
        applyAppearance()
    }

    private func updateTargetWindowFrame(_ windowID: CGWindowID) {
        guard let window = WindowCatalog.window(id: windowID) else {
            missingTargetTicks += 1
            if missingTargetTicks >= missingTargetLimit {
                panels.forEach { $0.orderOut(nil) }
                lastTargetFrame = nil
            }
            return
        }

        updateTargetWindowFrame(window)
    }

    private func updateTargetWindowFrame(_ window: WindowInfo) {
        missingTargetTicks = 0
        let rect = appKitRect(fromQuartzBounds: window.quartzBounds)
        guard let targetPanel = panels.first else { return }
        let targetChanged = lastTargetFrame != rect
        if targetChanged {
            imageGlobalFrame = nil
        }
        lastTargetFrame = rect

        if imageMask != nil {
            applyAppearance()
        } else if targetChanged {
            targetPanel.setFrame(rect, display: true)
            targetPanel.contentView?.frame = NSRect(origin: .zero, size: rect.size)
        }
        panels.dropFirst().forEach { $0.orderOut(nil) }
    }

    private func updateVisibility(raiseTargetOverlay: Bool = false) {
        panels.enumerated().forEach { index, panel in
            if isEnabled {
                if selectedWindowID == nil {
                    panel.orderFrontRegardless()
                } else if index == 0 {
                    if raiseTargetOverlay || !panel.isVisible {
                        orderTargetOverlay(panel)
                    }
                } else {
                    panel.orderOut(nil)
                }
            } else {
                panel.orderOut(nil)
            }
        }
    }

    private func orderTargetOverlay(_ panel: NSPanel) {
        if levelPreset == .strong {
            panel.orderFrontRegardless()
        } else if let selectedWindowID {
            panel.order(.above, relativeTo: Int(selectedWindowID))
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func overlayRect(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let width = max(80, screenFrame.width * widthRatio)
        let height = max(80, screenFrame.height * heightRatio)
        let availableX = max(0, screenFrame.width - width)
        let availableY = max(0, screenFrame.height - height)
        let x = screenFrame.minX + availableX * leftRatio
        let y = screenFrame.maxY - height - availableY * topRatio
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func applyManualFrame(_ frame: NSRect, on screen: NSScreen) {
        let screenFrame = screen.frame
        isApplyingManualDrag = true
        defer { isApplyingManualDrag = false }

        widthRatio = clampedSizeRatio(frame.width / screenFrame.width)
        heightRatio = clampedSizeRatio(frame.height / screenFrame.height)

        let availableX = max(1, screenFrame.width - frame.width)
        let availableY = max(1, screenFrame.height - frame.height)
        leftRatio = clampedPositionRatio((frame.minX - screenFrame.minX) / availableX)
        topRatio = clampedPositionRatio((screenFrame.maxY - frame.maxY) / availableY)
    }

    private func panImageViewport(dx: CGFloat, dy: CGFloat) {
        guard imageMask != nil, var frame = imageGlobalFrame else { return }

        frame.origin.x += dx
        frame.origin.y += dy
        imageGlobalFrame = snappedImageFrame(frame)
        applyAppearance()
    }

    private func zoomImageViewport(by factor: CGFloat) {
        guard imageMask != nil, var frame = imageGlobalFrame else { return }

        let clampedFactor = min(max(factor, 0.2), 5)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size.width = max(40, frame.width * clampedFactor)
        frame.size.height = max(40, frame.height * clampedFactor)
        frame.origin.x = center.x - frame.width / 2
        frame.origin.y = center.y - frame.height / 2
        imageGlobalFrame = snappedImageFrame(frame)
        applyAppearance()
    }

    private func cropImageFrame(left: CGFloat, right: CGFloat, bottom: CGFloat, top: CGFloat) {
        guard imageMask != nil, var rect = imageGlobalFrame else { return }

        let minimumSize: CGFloat = 80
        if left != 0, rect.width - left >= minimumSize {
            rect.origin.x += left
            rect.size.width -= left
        }
        if right != 0 {
            rect.size.width = max(minimumSize, rect.width + right)
        }
        if bottom != 0, rect.height - bottom >= minimumSize {
            rect.origin.y += bottom
            rect.size.height -= bottom
        }
        if top != 0 {
            rect.size.height = max(minimumSize, rect.height + top)
        }

        imageGlobalFrame = snappedImageFrame(rect)
        applyAppearance()
    }

    private func defaultImageFrame(for image: CGImage, targetFrame: NSRect) -> NSRect {
        let imageAspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        let height = max(1, targetFrame.height)
        let width = height * imageAspect
        return NSRect(x: targetFrame.minX, y: targetFrame.minY, width: width, height: height)
    }

    private func currentTargetFrame(for panel: NSPanel) -> NSRect {
        if let lastTargetFrame {
            return lastTargetFrame
        }

        guard let screen = panel.screen ?? NSScreen.main else {
            return panel.frame
        }

        return overlayRect(for: screen)
    }

    private func snappedImageFrame(_ frame: NSRect) -> NSRect {
        guard let targetFrame = lastTargetFrame ?? panels.first?.frame else { return frame }
        let threshold: CGFloat = 10
        var result = frame

        if abs(result.minX - targetFrame.minX) <= threshold {
            result.origin.x = targetFrame.minX
        }
        if abs(result.maxX - targetFrame.maxX) <= threshold {
            result.origin.x = targetFrame.maxX - result.width
        }
        if abs(result.minY - targetFrame.minY) <= threshold {
            result.origin.y = targetFrame.minY
        }
        if abs(result.maxY - targetFrame.maxY) <= threshold {
            result.origin.y = targetFrame.maxY - result.height
        }

        return result
    }

    private func appKitRect(fromQuartzBounds bounds: CGRect) -> NSRect {
        let mainScreenHeight = NSScreen.main?.frame.height ?? bounds.height
        return NSRect(
            x: bounds.minX,
            y: mainScreenHeight - bounds.minY - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    private func updateTrackingTimer() {
        trackingTimer?.invalidate()
        trackingTimer = nil

        guard selectedWindowID != nil else { return }

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.trackTargetWindow()
            }
        }
        timer.tolerance = 0.001
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func updateMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }

        guard selectedWindowID != nil else { return }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.restoreOverlayForTargetClick()
            }
        }
    }

    private func restoreOverlayForTargetClick() {
        guard
            isEnabled,
            selectedWindowID != nil,
            let targetFrame = lastTargetFrame,
            targetFrame.contains(NSEvent.mouseLocation),
            let panel = panels.first
        else {
            return
        }

        updateFrames()
        orderTargetOverlay(panel)
    }

    private func trackTargetWindow() {
        guard let selectedWindowID else {
            return
        }

        let windows = WindowCatalog.visibleWindows()
        guard let targetWindow = windows.first(where: { $0.id == selectedWindowID }) else {
            missingTargetTicks += 1
            if missingTargetTicks >= missingTargetLimit {
                panels.forEach { $0.orderOut(nil) }
                lastTargetFrame = nil
            }
            return
        }

        updateTargetWindowFrame(targetWindow)

        let targetIsFrontmost = windows.first?.id == selectedWindowID
        let targetPanelIsHidden = panels.first?.isVisible == false
        let targetIsVisible = windows.contains { $0.id == selectedWindowID }
        if targetIsFrontmost || targetPanelIsHidden || targetIsVisible {
            updateVisibility(raiseTargetOverlay: true)
        }
    }

    private func scheduleSpaceRecovery(after delay: TimeInterval) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.recoverVisibleOverlay()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func recoverVisibleOverlay() {
        guard isEnabled else { return }

        updateLevels()
        if selectedWindowID == nil {
            updateFrames()
            updateVisibility(raiseTargetOverlay: true)
            return
        }

        trackTargetWindow()
        if levelPreset == .strong {
            updateVisibility(raiseTargetOverlay: true)
        }
    }

    private func clampedSizeRatio(_ value: Double) -> Double {
        min(max(value, 0.08), 1.0)
    }

    private func clampedPositionRatio(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}

@main
struct VideoMaskOverlayApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
