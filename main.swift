import AppKit
import Foundation
import CoreServices

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
    var resetTimestamp: String?       // ISO8601 of when tokens reset
    enum CodingKeys: String, CodingKey {
        case timestamp
        case tokensAtLimit  = "tokens_at_limit"
        case resetTimestamp = "reset_timestamp"
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

/// Parse reset time from the Claude rate-limit message string.
/// Handles "resets in Xh Ym" and "resets 10pm (Australia/Melbourne)".
func parseResetTime(from text: String) -> Date? {
    // ── Duration format: "resets in 4h" / "resets in 4h 30m" ─────────────
    if text.range(of: "resets in", options: .caseInsensitive) != nil {
        var secs: TimeInterval = 0
        if let m = try? NSRegularExpression(pattern: "(\\d+)h").firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text) { secs += (Double(text[r]) ?? 0) * 3600 }
        if let m = try? NSRegularExpression(pattern: "(\\d+)m").firstMatch(
                in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text) { secs += (Double(text[r]) ?? 0) * 60 }
        return secs > 0 ? Date().addingTimeInterval(secs) : nil
    }

    // ── Specific time: "resets 10pm (Australia/Melbourne)" ────────────────
    guard let regex = try? NSRegularExpression(
              pattern: #"resets (\d+(?::\d+)?)(am|pm)(?:\s+\(([^)]+)\))?"#,
              options: .caseInsensitive),
          let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let tR = Range(m.range(at: 1), in: text),
          let aR = Range(m.range(at: 2), in: text) else { return nil }

    let timeStr = String(text[tR])
    let ispm    = String(text[aR]).lowercased() == "pm"
    let tzStr   = Range(m.range(at: 3), in: text).map { String(text[$0]) }

    var hour = 0, minute = 0
    if timeStr.contains(":") {
        let p = timeStr.split(separator: ":"); hour = Int(p[0]) ?? 0; minute = Int(p[1]) ?? 0
    } else { hour = Int(timeStr) ?? 0 }
    if ispm  && hour != 12 { hour += 12 }
    if !ispm && hour == 12 { hour  = 0  }

    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tzStr.flatMap { TimeZone(identifier: $0) } ?? .current

    let now = Date()
    var c = cal.dateComponents([.year, .month, .day], from: now)
    c.hour = hour; c.minute = minute; c.second = 0

    guard let candidate = cal.date(from: c) else { return nil }
    // If the time has already passed today, it must be tomorrow
    return candidate > now ? candidate : cal.date(byAdding: .day, value: 1, to: candidate)
}

// MARK: - Material Symbols token icon

func makeTokenIcon(ptSize: CGFloat = 14) -> NSImage {
    struct Once { static var done = false }
    if !Once.done {
        if let url = Bundle.main.url(forResource: "MaterialSymbolsRounded", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        Once.done = true
    }

    let tokenChar = "\u{EA25}"   // "token" glyph, FILL=1
    let scale: CGFloat = 2
    let px = Int(ptSize * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return NSImage() }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let variation: [NSNumber: NSNumber] = [
        0x46494C4C: 1, 0x77676874: 400, 0x47524144: 0, 0x6F70737A: 24,
    ]
    let desc = NSFontDescriptor(name: "Material Symbols Rounded", size: 0)
        .addingAttributes([.variation: variation])
    let font = NSFont(descriptor: desc, size: ptSize * scale)
             ?? NSFont.systemFont(ofSize: ptSize * scale)

    let attr = NSAttributedString(string: tokenChar, attributes: [
        .font: font, .foregroundColor: NSColor.black
    ])
    let sz = attr.size()
    attr.draw(at: CGPoint(x: (CGFloat(px) - sz.width) / 2,
                          y: (CGFloat(px) - sz.height) / 2))
    NSGraphicsContext.restoreGraphicsState()

    let img = NSImage(size: NSSize(width: ptSize, height: ptSize))
    img.addRepresentation(rep)
    img.isTemplate = true
    return img
}

// MARK: - Bar image

func makeBarImage(fraction: Double) -> NSImage {
    let ptW: CGFloat = 52, ptH: CGFloat = 15
    let scale: CGFloat = 2
    let pxW = Int(ptW * scale), pxH = Int(ptH * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return NSImage() }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let pad: CGFloat = 2, strokeW: CGFloat = 2
    let W = CGFloat(pxW), H = CGFloat(pxH)
    let r: CGFloat = (H - 2 * pad) / 4

    let outerPath = NSBezierPath(
        roundedRect: CGRect(x: pad, y: pad, width: W - 2*pad, height: H - 2*pad),
        xRadius: r, yRadius: r)
    outerPath.lineWidth = strokeW
    NSColor.black.setStroke()
    outerPath.stroke()

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
    img.isTemplate = true
    return img
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    let home        = URL(fileURLWithPath: NSHomeDirectory())
    lazy var statusFile = home.appendingPathComponent(".claude/token_status.json")
    lazy var limitsFile = home.appendingPathComponent(".claude/token_limits.json")
    lazy var hookScript = home.appendingPathComponent(".claude/scripts/token_tracker.py")

    var statusItem: NSStatusItem!
    var timer: Timer?

    // Dropdown info fields
    var histField        = NSTextField(labelWithString: "")
    var histView: NSView?
    var hintField        = NSTextField(labelWithString: "")   // shown only when calibrating
    var hintItem         = NSMenuItem()
    var usageField       = NSTextField(labelWithString: "")   // shown when calibrated
    var usageItem        = NSMenuItem()
    var undoItem         = NSMenuItem()
    var histSepItem      = NSMenuItem()
    var histHeaderItem   = NSMenuItem()
    var histBodyItem     = NSMenuItem()
    var histTrailSepItem = NSMenuItem()

    // FSEvents
    var fsEventStream:       FSEventStreamRef?
    var lastSeenRateLimitTs: Date?

    // Rate-limit / reset state
    var rateLimitResetAt:  Date?     // non-nil = showing countdown
    var refillingFraction: Double?   // non-nil = refill animation in progress
    var refillingTimer:    Timer?

    // MARK: Launch

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imageScaling = .scaleNone
        buildMenu()
        restoreRateLimitState()
        refresh()
        startWatchingTranscripts()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// On restart, if the last event's reset time is still in the future, resume countdown.
    func restoreRateLimitState() {
        guard let data      = try? Data(contentsOf: limitsFile),
              let limits    = try? JSONDecoder().decode(LimitsData.self, from: data),
              let last      = limits.events.last,
              let resetStr  = last.resetTimestamp,
              let resetDate = parseDate(resetStr),
              resetDate > Date() else { return }
        rateLimitResetAt = resetDate
    }

    // MARK: FSEvents — detect rate limit and reset

    func startWatchingTranscripts() {
        let dir    = home.appendingPathComponent(".claude/projects").path
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var ctx    = FSEventStreamContext(version: 0, info: selfPtr,
                                          retain: nil, release: nil, copyDescription: nil)

        let cb: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info = info else { return }
            let me    = Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self)
            for i in 0..<count {
                guard let p = paths[i] as? String, p.hasSuffix(".jsonl") else { continue }
                me.checkForRateLimit(in: p)
                if me.rateLimitResetAt != nil { me.checkForReset(in: p) }
            }
        }

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, cb, &ctx, [dir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        fsEventStream = stream
    }

    func checkForRateLimit(in path: String) {
        guard let fh = FileHandle(forReadingAtPath: path) else { return }
        defer { fh.closeFile() }
        let end = fh.seekToEndOfFile()
        fh.seek(toFileOffset: end - min(end, 8192))
        guard let text = String(data: fh.readDataToEndOfFile(), encoding: .utf8) else { return }

        for line in text.components(separatedBy: "\n").reversed() {
            guard line.contains("rate_limit"), line.contains("isApiErrorMessage") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let obj      = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let tsStr    = obj["timestamp"] as? String,
                  let ts       = parseDate(tsStr) else { continue }

            if let last = lastSeenRateLimitTs, ts <= last { return }
            lastSeenRateLimitTs = ts

            // Try to parse exact reset time from the message content
            var resetTime: Date? = nil
            if let msg     = obj["message"] as? [String: Any],
               let content = msg["content"] as? [[String: Any]],
               let msgText = content.first?["text"] as? String {
                resetTime = parseResetTime(from: msgText)
            }
            // Fall back to 5-hour estimate
            let resolvedReset = resetTime ?? Date().addingTimeInterval(5 * 3600)

            DispatchQueue.main.async { [weak self] in
                self?.doRecordLimit(resetTime: resolvedReset)
            }
            return
        }
    }

    /// After a rate limit, watch for the first successful assistant response — that means reset.
    func checkForReset(in path: String) {
        guard let rateLimitTs = lastSeenRateLimitTs else { return }
        guard let fh = FileHandle(forReadingAtPath: path) else { return }
        defer { fh.closeFile() }
        let end = fh.seekToEndOfFile()
        fh.seek(toFileOffset: end - min(end, 4096))
        guard let text = String(data: fh.readDataToEndOfFile(), encoding: .utf8) else { return }

        for line in text.components(separatedBy: "\n").reversed() {
            guard (line.contains("\"type\":\"assistant\"") || line.contains("\"type\": \"assistant\"")),
                  !line.contains("\"error\":\"rate_limit\""),
                  !line.contains("\"error\": \"rate_limit\"") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let obj      = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let tsStr    = obj["timestamp"] as? String,
                  let ts       = parseDate(tsStr),
                  ts > rateLimitTs.addingTimeInterval(5) else { continue }  // must be after limit

            DispatchQueue.main.async { [weak self] in self?.handleReset() }
            return
        }
    }

    // MARK: Reset / Refill animation

    func handleReset() {
        rateLimitResetAt  = nil
        lastSeenRateLimitTs = nil   // allow next rate limit to be detected fresh
        startRefillAnimation()
    }

    func startRefillAnimation() {
        refillingFraction = 0.0
        refillingTimer?.invalidate()
        let duration: Double = 1.5
        let interval: Double = 1.0 / 20   // 20 fps
        let steps = duration / interval
        var step  = 0.0

        refillingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            step += 1
            let progress = step / steps
            if progress >= 1 {
                self.refillingFraction = nil   // done
                t.invalidate()
                self.refillingTimer = nil
            } else {
                self.refillingFraction = 1 - pow(1 - progress, 3)   // ease-out cubic
            }
            self.updateMenuBarButton(windowTotal: 0, limit: 1,
                                     sessionTotal: 0, isCalibrated: true)
        }
    }

    // MARK: Menu bar button

    func updateMenuBarButton(windowTotal: Int, limit: Int?, sessionTotal: Int, isCalibrated: Bool) {
        // 1. Refill animation
        if let frac = refillingFraction {
            statusItem.button?.image    = makeBarImage(fraction: frac)
            statusItem.button?.title    = ""
            return
        }

        // 2. Countdown when rate limited
        if let resetAt = rateLimitResetAt {
            let rem = max(0, resetAt.timeIntervalSinceNow)
            let h = Int(rem) / 3600
            let m = (Int(rem) % 3600) / 60
            let s = Int(rem) % 60
            let display: String
            if      h > 0  { display = "\(h)h \(m)m" }
            else if m >= 2 { display = "\(m)m" }
            else if m == 1 { display = "1m \(s)s" }
            else           { display = "\(s)s" }

            let img = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)
            img?.isTemplate = true
            statusItem.button?.image         = img
            statusItem.button?.imagePosition = .imageLeft
            statusItem.button?.title         = "\u{2009}\(display)"
            return
        }

        // 3. Calibrated: bar EMPTIES as tokens are used
        if isCalibrated, let limit = limit, limit > 0 {
            let frac = 1.0 - Double(windowTotal) / Double(limit)
            statusItem.button?.image = makeBarImage(fraction: max(0, frac))
            statusItem.button?.title = ""
            return
        }

        // 4. Calibrating: icon + raw count
        statusItem.button?.image         = makeTokenIcon()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.title         = "\u{2009}\(fmt(sessionTotal))"
    }

    // MARK: Menu

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
        let lineH: CGFloat = 18, w: CGFloat = 260
        field.frame = NSRect(x: lpad, y: vpad, width: w - lpad - rpad, height: lineH * CGFloat(lines))
        let view = NSView(frame: NSRect(x: 0, y: 0, width: w, height: lineH * CGFloat(lines) + 2 * vpad))
        view.addSubview(field)

        let item = NSMenuItem()
        item.isEnabled = false
        item.view = view
        return item
    }

    func makeBoldHeader(_ text: String) -> NSMenuItem {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        field.textColor = .labelColor
        field.isEditable = false; field.isSelectable = false
        field.isBezeled  = false; field.drawsBackground = false
        field.sizeToFit()

        let lpad: CGFloat = 14, vpad: CGFloat = 4, w: CGFloat = 260
        field.frame = NSRect(x: lpad, y: vpad, width: w - lpad - 14, height: field.frame.height)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: w,
                                        height: field.frame.height + 2 * vpad))
        view.addSubview(field)
        let item = NSMenuItem(); item.isEnabled = false; item.view = view
        return item
    }

    func buildMenu() {
        let m = NSMenu()
        m.autoenablesItems = false

        // Usage row — shown only when calibrated
        usageItem = makeInfoItem(field: usageField)
        usageField.textColor = .secondaryLabelColor
        m.addItem(usageItem)

        histSepItem = .separator()
        m.addItem(histSepItem)
        histHeaderItem = makeBoldHeader("History")
        m.addItem(histHeaderItem)
        let histMenuItem = makeInfoItem(field: histField, lines: 1)
        histView = histMenuItem.view
        histBodyItem = histMenuItem
        m.addItem(histBodyItem)

        histTrailSepItem = .separator()
        m.addItem(histTrailSepItem)

        m.addItem(makeBoldHeader("Actions"))

        // Hint — shown only when calibrating
        hintItem = makeInfoItem(field: hintField, lines: 3)
        hintField.textColor = .secondaryLabelColor
        hintField.stringValue = "Tracker calibrates after you register your tokens running out for the first time"
        m.addItem(hintItem)

        let ran = NSMenuItem(title: "My tokens ran out",
                             action: #selector(recordLimit), keyEquivalent: "")
        ran.target = self
        m.addItem(ran)

        undoItem.title = "Undo"; undoItem.action = #selector(removeLastLimit)
        undoItem.target = self
        m.addItem(undoItem)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit",
                             action: #selector(NSApplication.terminate(_:)),
                             keyEquivalent: "q"))
        statusItem.menu = m
    }

    // MARK: Refresh

    func refresh() {
        // Check if countdown just expired
        if let resetAt = rateLimitResetAt, resetAt <= Date() {
            rateLimitResetAt = nil
            startRefillAnimation()
        }

        guard let data   = try? Data(contentsOf: statusFile),
              let status = try? JSONDecoder().decode(TokenStatus.self, from: data) else {
            DispatchQueue.main.async { self.statusItem.button?.title = "⬡ —" }
            return
        }

        let limits = (try? JSONDecoder().decode(
            LimitsData.self, from: (try? Data(contentsOf: limitsFile)) ?? Data()
        )) ?? LimitsData(events: [])

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let isCalibrated = status.limitEventCount >= 1 && status.estimatedLimit != nil

            // ── Menu bar button ──────────────────────────────────────────
            self.updateMenuBarButton(
                windowTotal:  status.window.total,
                limit:        status.estimatedLimit,
                sessionTotal: status.session.total,
                isCalibrated: isCalibrated
            )

            // ── Usage / History block — shown when calibrated ────────────
            self.usageItem.isHidden        = !isCalibrated
            self.histSepItem.isHidden      = !isCalibrated
            self.histHeaderItem.isHidden   = !isCalibrated
            self.histBodyItem.isHidden     = !isCalibrated
            self.histTrailSepItem.isHidden = !isCalibrated
            self.hintItem.isHidden         = isCalibrated
            self.undoItem.isHidden         = !isCalibrated

            if isCalibrated, let limit = status.estimatedLimit, limit > 0 {
                self.usageField.stringValue = "\(fmt(status.window.total)) / \(fmt(limit))"
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

            let lineCount = max(1, evList.isEmpty ? 1 : evList.count)
            let lineH: CGFloat = 18, vpad: CGFloat = 2
            self.histField.frame.size.height = lineH * CGFloat(lineCount)
            self.histView?.frame.size.height  = lineH * CGFloat(lineCount) + 2 * vpad
        }
    }

    // MARK: Record limit

    @objc func recordLimit() {
        // Manual trigger — estimate reset as 5h from now
        doRecordLimit(resetTime: Date().addingTimeInterval(5 * 3600))
    }

    func doRecordLimit(resetTime: Date) {
        guard let data   = try? Data(contentsOf: statusFile),
              let status = try? JSONDecoder().decode(TokenStatus.self, from: data) else { return }

        var limits = (try? JSONDecoder().decode(
            LimitsData.self, from: (try? Data(contentsOf: limitsFile)) ?? Data()
        )) ?? LimitsData(events: [])

        let iso      = ISO8601DateFormatter()
        var event    = LimitEvent(timestamp: iso.string(from: Date()),
                                  tokensAtLimit: status.window.total)
        event.resetTimestamp = iso.string(from: resetTime)
        limits.events.append(event)
        try? JSONEncoder().encode(limits).write(to: limitsFile)

        rateLimitResetAt = resetTime

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments     = [hookScript.path]
        task.standardInput = FileHandle.nullDevice
        try? task.run()

        refresh()
    }

    @objc func removeLastLimit() {
        var limits = (try? JSONDecoder().decode(
            LimitsData.self, from: (try? Data(contentsOf: limitsFile)) ?? Data()
        )) ?? LimitsData(events: [])

        guard !limits.events.isEmpty else { return }
        limits.events.removeLast()
        try? JSONEncoder().encode(limits).write(to: limitsFile)

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

        // Restore countdown from the new last event (if still valid)
        if let last      = limits.events.last,
           let resetStr  = last.resetTimestamp,
           let resetDate = parseDate(resetStr),
           resetDate > Date() {
            rateLimitResetAt = resetDate
        } else {
            rateLimitResetAt = nil
        }

        refresh()
    }
}

// MARK: - Entry point

let app      = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
