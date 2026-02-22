import AppKit
import Foundation

// MARK: - Models

struct TokenStatus: Codable {
    let updatedTs: String
    let session: Counts
    let window: Counts
    let windowStart: String?
    let estimatedLimit: Int?
    let limitEventCount: Int

    enum CodingKeys: String, CodingKey {
        case updatedTs = "updated_ts"
        case session, window
        case windowStart = "window_start"
        case estimatedLimit = "estimated_limit"
        case limitEventCount = "limit_event_count"
    }
}

struct Counts: Codable {
    let input, output, total: Int
    let cacheWrite, cacheRead: Int
    enum CodingKeys: String, CodingKey {
        case input, output, total
        case cacheWrite = "cache_write"
        case cacheRead  = "cache_read"
    }
}

struct LimitEvent: Codable {
    let timestamp: String
    let tokensAtLimit: Int
    enum CodingKeys: String, CodingKey {
        case timestamp
        case tokensAtLimit = "tokens_at_limit"
    }
}

struct LimitsData: Codable {
    var events: [LimitEvent]
}

// MARK: - Helpers

func fmt(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.2fM", Double(n) / 1e6)
    case 1_000...:     return String(format: "%.1fK", Double(n) / 1e3)
    default:           return "\(n)"
    }
}

func parseDate(_ s: String) -> Date? {
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }

    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    if let d = f2.date(from: s) { return d }

    let f3 = DateFormatter()
    f3.locale = Locale(identifier: "en_US_POSIX")
    f3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
    return f3.date(from: s)
}

// MARK: - Material Symbols token icon

func makeTokenIcon(ptSize: CGFloat = 14) -> NSImage {
    // Register the bundled Material Symbols Rounded font once
    struct Once { static var done = false }
    if !Once.done {
        if let url = Bundle.main.url(forResource: "MaterialSymbolsRounded", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        Once.done = true
    }

    // "token" glyph = U+EA25, FILL axis = 1 (filled variant)
    let tokenChar = "\u{EA25}"
    let scale: CGFloat = 2
    let px = Int(ptSize * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return NSImage() }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Build font with FILL=1 axis for the filled variant via NSFontDescriptor
    // Variation dict keys are 4-byte FourCC axis tags as integers
    let variation: [NSNumber: NSNumber] = [
        0x46494C4C: 1,    // FILL = 1 (filled)
        0x77676874: 400,  // wght = 400
        0x47524144: 0,    // GRAD = 0
        0x6F70737A: 24,   // opsz = 24
    ]
    let desc = NSFontDescriptor(name: "Material Symbols Rounded", size: 0)
        .addingAttributes([.variation: variation])
    let font = NSFont(descriptor: desc, size: ptSize * scale) ?? NSFont.systemFont(ofSize: ptSize * scale)

    let attr = NSAttributedString(string: tokenChar, attributes: [
        .font: font,
        .foregroundColor: NSColor.black
    ])
    let size = attr.size()
    let origin = CGPoint(x: (CGFloat(px) - size.width) / 2,
                         y: (CGFloat(px) - size.height) / 2)
    attr.draw(at: origin)

    NSGraphicsContext.restoreGraphicsState()

    let img = NSImage(size: NSSize(width: ptSize, height: ptSize))
    img.addRepresentation(rep)
    img.isTemplate = true
    return img
}

// MARK: - Bar image (native AppKit — crisp on all displays)

func makeBarImage(fraction: Double) -> NSImage {
    let ptW: CGFloat = 52, ptH: CGFloat = 15
    let scale: CGFloat = 2
    let pxW = Int(ptW * scale)   // 104
    let pxH = Int(ptH * scale)   // 30

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pxW,
        pixelsHigh: pxH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return NSImage() }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let pad: CGFloat     = 2
    let strokeW: CGFloat = 2
    let W = CGFloat(pxW), H = CGFloat(pxH)
    let r: CGFloat       = (H - 2 * pad) / 4

    // Outer border
    let outerPath = NSBezierPath(
        roundedRect: CGRect(x: pad, y: pad, width: W - 2*pad, height: H - 2*pad),
        xRadius: r, yRadius: r
    )
    outerPath.lineWidth = strokeW
    NSColor.black.setStroke()
    outerPath.stroke()

    // Inner fill — square left corners (flush), rounded right corners only.
    // Stroke is centred on its path so the inner edge is at pad + strokeW/2.
    let f      = max(0, min(1, fraction))
    let innerX = pad + strokeW / 2
    let innerY = pad + strokeW / 2
    let innerH = H - 2 * pad - strokeW
    let fillW  = (W - 2 * pad - strokeW) * f
    let fr     = max(1, r - strokeW / 2)

    if fillW > 0 {
        let path = NSBezierPath()
        if fillW <= fr {
            path.appendRect(CGRect(x: innerX, y: innerY, width: fillW, height: innerH))
        } else {
            path.move(to: CGPoint(x: innerX, y: innerY))
            path.line(to: CGPoint(x: innerX + fillW - fr, y: innerY))
            path.appendArc(withCenter: CGPoint(x: innerX + fillW - fr, y: innerY + fr),
                           radius: fr, startAngle: 270, endAngle: 0, clockwise: false)
            path.line(to: CGPoint(x: innerX + fillW, y: innerY + innerH - fr))
            path.appendArc(withCenter: CGPoint(x: innerX + fillW - fr, y: innerY + innerH - fr),
                           radius: fr, startAngle: 0, endAngle: 90, clockwise: false)
            path.line(to: CGPoint(x: innerX, y: innerY + innerH))
            path.close()
        }
        NSColor.black.setFill()
        path.fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    let img = NSImage(size: NSSize(width: ptW, height: ptH))
    img.addRepresentation(rep)
    img.isTemplate = true   // lets macOS handle dark/light adaptation automatically
    return img
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let home       = URL(fileURLWithPath: NSHomeDirectory())
    lazy var statusFile = home.appendingPathComponent(".claude/token_status.json")
    lazy var limitsFile = home.appendingPathComponent(".claude/token_limits.json")
    lazy var hookScript = home.appendingPathComponent(".claude/scripts/token_tracker.py")

    var statusItem: NSStatusItem!
    var timer: Timer?

    // Info text fields — updated in refresh(); backed by custom NSMenuItem views.
    // isEnabled=false on those items blocks hover without greying out custom views.
    var sessionField = NSTextField(labelWithString: "")
    var usedField    = NSTextField(labelWithString: "")
    var histField    = NSTextField(labelWithString: "")
    var histView: NSView?   // kept so refresh() can resize it to fit actual line count

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imageScaling = .scaleNone
        buildMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: Menu

    // Returns a non-interactive info item. The custom view means the system never
    // greys it out (disabled only suppresses hover on the menu row, not view content).
    func makeInfoItem(field: NSTextField, lines: Int = 1) -> NSMenuItem {
        field.font               = NSFont.menuFont(ofSize: 0)
        field.textColor          = .labelColor
        field.isEditable         = false
        field.isSelectable       = false
        field.isBezeled          = false
        field.drawsBackground    = false
        field.maximumNumberOfLines = lines
        field.lineBreakMode      = lines > 1 ? .byWordWrapping : .byTruncatingTail

        let lpad: CGFloat = 14, rpad: CGFloat = 14, vpad: CGFloat = 2
        let lineH: CGFloat = 18
        let w: CGFloat = 260

        field.frame = NSRect(x: lpad, y: vpad, width: w - lpad - rpad, height: lineH * CGFloat(lines))
        let view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: lineH * CGFloat(lines) + 2 * vpad))
        view.addSubview(field)

        let item = NSMenuItem()
        item.isEnabled = false   // no hover; custom view ignores this for colour
        item.view = view
        return item
    }

    func makeBoldHeader(_ text: String) -> NSMenuItem {
        let field = NSTextField(labelWithString: text)
        field.font            = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        field.textColor       = .labelColor
        field.isEditable      = false
        field.isSelectable    = false
        field.isBezeled       = false
        field.drawsBackground = false
        field.sizeToFit()

        let lpad: CGFloat = 14, vpad: CGFloat = 4
        let w: CGFloat = 260
        field.frame = NSRect(x: lpad, y: vpad, width: w - lpad - 14, height: field.frame.height)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: field.frame.height + 2 * vpad))
        view.addSubview(field)

        let item = NSMenuItem()
        item.isEnabled = false
        item.view = view
        return item
    }

    func buildMenu() {
        let m = NSMenu()
        m.autoenablesItems = false

        m.addItem(makeInfoItem(field: sessionField))
        m.addItem(makeInfoItem(field: usedField))
        m.addItem(.separator())
        m.addItem(makeBoldHeader("Limit history"))
        let histMenuItem = makeInfoItem(field: histField, lines: 1)
        histView = histMenuItem.view
        m.addItem(histMenuItem)
        m.addItem(.separator())

        let ran = NSMenuItem(title: "My tokens ran out",
                             action: #selector(recordLimit),
                             keyEquivalent: "")
        ran.target = self
        m.addItem(ran)

        let rem = NSMenuItem(title: "Undo last event",
                             action: #selector(removeLastLimit),
                             keyEquivalent: "")
        rem.target = self
        m.addItem(rem)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit",
                             action: #selector(NSApplication.terminate(_:)),
                             keyEquivalent: "q"))
        statusItem.menu = m
    }

    // MARK: Refresh

    func refresh() {
        guard
            let data   = try? Data(contentsOf: statusFile),
            let status = try? JSONDecoder().decode(TokenStatus.self, from: data)
        else {
            DispatchQueue.main.async { self.statusItem.button?.title = "⬡ —" }
            return
        }

        let limits = (try? JSONDecoder().decode(
            LimitsData.self,
            from: (try? Data(contentsOf: limitsFile)) ?? Data()
        )) ?? LimitsData(events: [])

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let w = status.window

            // ── Menu bar button ──────────────────────────────────────────
            if let limit = status.estimatedLimit, status.limitEventCount >= 1 {
                let frac = Double(w.total) / Double(limit)
                self.statusItem.button?.image = makeBarImage(fraction: frac)
                self.statusItem.button?.title = ""
            } else {
                self.statusItem.button?.image = makeTokenIcon()
                self.statusItem.button?.imagePosition = .imageLeft
                self.statusItem.button?.title = " \(fmt(status.session.total))"
            }

            // ── Dropdown ─────────────────────────────────────────────────
            if let limit = status.estimatedLimit, status.limitEventCount >= 1 {
                let pct = Int(Double(status.session.total) / Double(limit) * 100)
                self.sessionField.stringValue = "This session: \(pct)%"
                self.usedField.stringValue    = "Used \(fmt(w.total)) of \(fmt(limit)) tokens"
            } else {
                self.sessionField.stringValue = "This session: \(fmt(status.session.total)) tokens"
                self.usedField.stringValue    = "Tap 'My tokens ran out' to calibrate"
            }

            let evList = limits.events.suffix(4)
            if evList.isEmpty {
                self.histField.stringValue = "No events yet"
            } else {
                let hFmt = DateFormatter()
                hFmt.dateFormat = "MMM d, HH:mm"
                self.histField.stringValue = evList.map { e in
                    let d = parseDate(e.timestamp) ?? Date()
                    return "\(hFmt.string(from: d))  →  \(fmt(e.tokensAtLimit))"
                }.joined(separator: "\n")
            }

            // Resize histView to fit exact line count — no wasted whitespace
            let lineCount  = max(1, evList.isEmpty ? 1 : evList.count)
            let lineH: CGFloat = 18, vpad: CGFloat = 2
            let newH = lineH * CGFloat(lineCount) + 2 * vpad
            self.histField.frame.size.height = lineH * CGFloat(lineCount)
            self.histView?.frame.size.height = newH
        }
    }

    // MARK: Record limit

    @objc func recordLimit() {
        guard
            let data   = try? Data(contentsOf: statusFile),
            let status = try? JSONDecoder().decode(TokenStatus.self, from: data)
        else { return }

        var limits = (try? JSONDecoder().decode(
            LimitsData.self,
            from: (try? Data(contentsOf: limitsFile)) ?? Data()
        )) ?? LimitsData(events: [])

        let iso = ISO8601DateFormatter()
        limits.events.append(LimitEvent(
            timestamp:     iso.string(from: Date()),
            tokensAtLimit: status.window.total
        ))
        try? JSONEncoder().encode(limits).write(to: limitsFile)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments     = [hookScript.path]
        task.standardInput = FileHandle.nullDevice
        try? task.run()

        refresh()
    }

    @objc func removeLastLimit() {
        var limits = (try? JSONDecoder().decode(
            LimitsData.self,
            from: (try? Data(contentsOf: limitsFile)) ?? Data()
        )) ?? LimitsData(events: [])

        guard !limits.events.isEmpty else { return }
        limits.events.removeLast()
        try? JSONEncoder().encode(limits).write(to: limitsFile)

        // Patch token_status.json in-place — recalculate only the event-derived
        // fields (estimated_limit, limit_event_count, window_start) so session
        // and window totals are preserved and the display doesn't flash to zero.
        if let data = try? Data(contentsOf: statusFile),
           var obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            let vals = limits.events.map { $0.tokensAtLimit }.sorted()
            let mid  = vals.count / 2
            let est: Any = vals.isEmpty ? NSNull() :
                           (vals.count % 2 != 0 ? vals[mid] : (vals[mid-1] + vals[mid]) / 2)

            obj["limit_event_count"] = limits.events.count
            obj["estimated_limit"]   = est
            obj["window_start"]      = limits.events.last?.timestamp ?? NSNull()

            if let updated = try? JSONSerialization.data(withJSONObject: obj) {
                try? updated.write(to: statusFile)
            }
        }

        refresh()
    }
}

// MARK: - Entry point

let app      = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
