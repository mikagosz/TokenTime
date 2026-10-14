import AppKit
import SwiftUI

// The Help window: a big title, then sections with a picture of the app on one side and the steps on the
// other, sides taking turns. Numbered points on a picture match the numbered steps.
//
// The pictures are drawn by TokenTime itself, on sample data: the panel, the two entry popovers and Settings
// are rendered off screen from the very same SwiftUI views, fed with made-up accounts in a store of their own
// (`AccountStore(fileURL: nil, defaults:)`) — no iCloud file, and the real local cache is never read or written.

@MainActor
final class HelpWindow {
    static let shared = HelpWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = HelpContent.windowTitle.current
            w.isReleasedWhenClosed = false
            // The window first, the pictures once it is on screen: drawing them holds the run loop for a moment.
            w.contentView = NSHostingView(rootView: HelpRoot())
            // A fixed height: an `idealHeight` alone gave the window 432 pt (measured in DeskMount 0.1.50).
            w.setContentSize(NSSize(width: HelpPage.width, height: HelpPage.height))
            w.center()
            window = w
        }
        // A menu bar app is never active by itself: without this the window opens behind the others.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Sample data

/// Made-up accounts in a settings store of their own, removed once the pictures are made.
@MainActor
enum HelpSample {
    static let suite = "com.mikagosz.tokentime.help-sample"

    static func with<T>(_ make: @MainActor (AccountStore) -> T) -> T {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AccountStore(fileURL: nil, observeTermination: false, defaults: defaults)
        store.showAsSynced()
        let now = Date()
        store.accounts = [
            Account(name: loc.t("Praca", "Work"), resetDate: now.addingTimeInterval(3 * 3600 + 12 * 60), windowHours: 5,
                    computers: [.macMini, .macBook], weeklyReset: WeeklyReset.parse("Sat 12 AM")),
            Account(name: loc.t("Dom", "Home"), resetDate: now.addingTimeInterval(42 * 60), windowHours: 5, computers: [.iMac]),
            Account(name: loc.t("Zapasowe", "Spare"), resetDate: now.addingTimeInterval(-10 * 60), windowHours: 5, computers: [.macStudio]),
        ]
        return make(store)
    }
}

/// Bitmaps of the app's own views on sample data, made when the Help window opens.
@MainActor
struct HelpPictures {
    let label: NSImage
    let panel: NSImage
    let entry: NSImage
    let weekly: NSImage
    let settings: NSImage

    static let panelSize = NSSize(width: 320, height: 450)

    static func make() -> HelpPictures {
        HelpSample.with { store in
            // On the window's own background: a borderless window has none, and white text came out on white.
            @MainActor func fitted<V: View>(_ view: V) -> NSImage {
                let drawn = view.fixedSize().background(Color(nsColor: .windowBackgroundColor))
                let size = NSHostingController(rootView: drawn).sizeThatFits(in: CGSize(width: 600, height: 1000))
                return Render.window(drawn, size: size, titled: false, title: "", settle: 0.15)
            }
            return HelpPictures(
                label: fitted(MenuBarLabel(store: store).padding(.horizontal, 10).frame(height: 24)),
                panel: Render.window(MenuBarView().environment(store).background(Color(nsColor: .windowBackgroundColor)), size: panelSize, titled: false, title: "", settle: 0.3),
                entry: fitted(DurationEntry(text: "3:30") { _ in }),
                weekly: fitted(WeeklyResetEntry(current: WeeklyReset.parse("Sat 12 AM")) { _ in }),
                settings: fitted(SettingsView().environment(store)))
        }
    }
}

@MainActor
enum Render {
    /// A view drawn into a bitmap at twice its size, so it stays sharp on a Retina screen.
    static func bitmap(_ v: NSView) -> NSImage {
        let b = v.bounds
        guard b.width >= 1, b.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * 2), pixelsHigh: Int(b.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return NSImage() }
        rep.size = b.size
        v.cacheDisplay(in: b, to: rep)
        let image = NSImage(size: b.size)
        image.addRepresentation(rep)
        return image
    }

    /// A window's content rendered off screen and invisible, in a real titled window so its toolbar is drawn
    /// too — the whole frame is the bitmap, the content running under the title bar as in the app.
    /// `titled: false` draws the content alone (the page export).
    /// `settle`: how long the run loop turns first, for the folder walk and the editor's late layout.
    static func window<V: View>(_ view: V, size: NSSize, titled: Bool = true, title: String, settle: TimeInterval) -> NSImage {
        // Drawn as the window in front: an invisible window is never key, and its controls would be drawn dimmed.
        let controller = NSHostingController(rootView: view.environment(\.controlActiveState, .key))
        controller.sizingOptions = []
        let w = NSWindow(contentViewController: controller)
        w.styleMask = titled ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless]
        w.isReleasedWhenClosed = false
        w.title = title
        w.appearance = NSApp.effectiveAppearance
        w.alphaValue = 0
        w.ignoresMouseEvents = true
        w.setContentSize(size)
        w.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        w.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(settle))
        let frame = (titled ? w.contentView?.superview : w.contentView) ?? NSView()
        // The sidebar's material blends with what is behind the window, which a bitmap never sees.
        let plain = NSAppearance(named: w.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) ?? .aqua)
        func withinWindow(_ v: NSView) {
            if let effect = v as? NSVisualEffectView {
                effect.blendingMode = .withinWindow
                effect.state = .active
                // Its vibrant appearance draws the list's text through the missing backdrop, dimmed.
                effect.appearance = plain
            }
            if v.appearance?.name.rawValue.contains("Vibrant") == true { v.appearance = plain }
            v.subviews.forEach(withinWindow)
        }
        withinWindow(frame)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        frame.layoutSubtreeIfNeeded()
        frame.display()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        var image = NSImage()
        w.effectiveAppearance.performAsCurrentDrawingAppearance { image = bitmap(frame) }
        w.orderOut(nil)
        w.contentViewController = nil
        return image
    }
}

extension NSImage {
    /// A piece of the picture, in points from its top-left corner — like a cut-out screenshot.
    func cutOut(_ r: CGRect) -> NSImage {
        if r == CGRect(origin: .zero, size: size) { return self }
        return NSImage(size: r.size, flipped: false) { _ in
            self.draw(in: NSRect(x: -r.minX, y: r.maxY - self.size.height, width: self.size.width, height: self.size.height),
                      from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}

// MARK: - The page

/// The window's content: a spinner while the pictures are drawn, then the page.
private struct HelpRoot: View {
    @State private var pictures: HelpPictures?

    var body: some View {
        if let pictures {
            HelpPage(pictures: pictures)
        } else {
            ProgressView()
                .frame(width: HelpPage.width, height: HelpPage.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .onAppear {
                    // A moment later, so the window with the spinner is drawn before the run loop is held.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pictures = HelpPictures.make() }
                }
        }
    }
}

struct HelpPage: View {
    static let width: CGFloat = 960
    static var height: CGFloat { min(900, (NSScreen.main?.visibleFrame.height ?? 900) - 80) }

    let pictures: HelpPictures
    /// For the bitmap of the whole page (`--export-help`): no scrolling, every section unfolded.
    var wholePage = false

    var body: some View {
        if wholePage {
            content.frame(width: Self.width).background(Color(nsColor: .windowBackgroundColor))
        } else {
            // Opens at the title: without the anchor the window came up scrolled a little way down.
            ScrollView { content }
                .defaultScrollAnchor(.top)
                .frame(width: Self.width, height: Self.height)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            ForEach(Array(HelpContent.sections.enumerated()), id: \.offset) { i, s in
                Divider().padding(.horizontal, 60)
                HelpSectionView(section: s, pictureLeft: i % 2 == 0, pictures: pictures, expanded: wholePage)
            }
            Divider().padding(.horizontal, 60)
            goodToKnow
            FractalSignature()
        }
        .padding(.bottom, 40)
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 96, height: 96)
            Text(verbatim: HelpContent.title.current).font(.system(size: 40, weight: .semibold))
            Text(verbatim: HelpContent.intro.current)
                .font(.system(size: 17)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(4)
                .frame(maxWidth: 640)
                .fixedSize(horizontal: false, vertical: true)
            WindowPicture(image: pictures.panel, crop: Crop(rect: CGRect(origin: .zero, size: HelpPictures.panelSize), points: []))
                .padding(.top, 8)
        }
        .padding(.top, 44).padding(.bottom, 48).padding(.horizontal, 60)
    }

    private var goodToKnow: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: HelpContent.goodToKnow.current).font(.system(size: 30, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20, alignment: .top), GridItem(.flexible(), spacing: 20, alignment: .top)],
                      spacing: 20) {
                ForEach(HelpContent.cards, id: \.symbol) { c in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: c.symbol).font(.system(size: 22)).foregroundStyle(Color.accentColor)
                        Text(verbatim: c.title.current).font(.headline)
                        Text(verbatim: c.text.current).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
                }
            }
        }
        .padding(.top, 40).padding(.horizontal, 60)
    }
}

private struct HelpSectionView: View {
    let section: HelpContent.Section
    let pictureLeft: Bool
    let pictures: HelpPictures
    @State var expanded: Bool

    /// TokenTime's windows are all narrow: no section needs the whole width.
    private var wide: Bool { false }

    var body: some View {
        Group {
            if wide {
                VStack(alignment: .leading, spacing: 28) {
                    text
                    picture.frame(maxWidth: .infinity)
                }
            } else {
                HStack(alignment: .center, spacing: 44) {
                    if pictureLeft { picture }
                    text
                    if !pictureLeft { picture }
                }
            }
        }
        .padding(.vertical, 44).padding(.horizontal, 60)
    }

    private var picture: some View {
        Group {
            switch section.picture {
            case .label: MenuBarPicture(image: pictures.label)
            case .panel: WindowPicture(image: pictures.panel, crop: HelpCrops.panel)
            case .card: WindowPicture(image: pictures.panel, crop: HelpCrops.card)
            case .entry: WindowPicture(image: pictures.entry, crop: HelpCrops.entry(pictures.entry.size))
            case .states: WindowPicture(image: pictures.panel, crop: HelpCrops.states)
            case .weekly: WindowPicture(image: pictures.weekly, crop: HelpCrops.weekly(pictures.weekly.size))
            case .macs: WindowPicture(image: pictures.settings, crop: HelpCrops.macs(pictures.settings.size))
            }
        }
        .frame(width: wide ? nil : 440)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: section.title.current).font(.system(size: 30, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: section.lead.current).font(.system(size: 15)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(section.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Marker(number: i + 1, small: true)
                        Text(verbatim: step.current).font(.system(size: 14)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let more = section.more {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Label(expanded ? HelpContent.less.current : HelpContent.more.current,
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.link)
                if expanded {
                    Text(verbatim: more.current).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The menu bar strip, drawn with the app's own label in it: a menu bar cannot be rendered.
private struct MenuBarPicture: View {
    let image: NSImage

    var body: some View {
        Frame {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "wifi").foregroundStyle(.secondary)
                    Image(nsImage: image)
                        .overlay(alignment: .bottomLeading) { Marker(number: 1).offset(x: 2, y: 30) }
                        .overlay(alignment: .bottomTrailing) { Marker(number: 2).offset(x: -6, y: 30) }
                    Image(systemName: "battery.75percent").foregroundStyle(.secondary)
                    Text(verbatim: "9:41").font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Color.primary.opacity(0.08))
                // Above the blank below, or that blank covers the points hanging under the bar.
                .zIndex(1)
                Color(nsColor: .windowBackgroundColor).frame(height: 70)
            }
            .frame(width: 440)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - Cut-outs and points

/// Where to cut a window and where its numbered points stand, in points of the window.
/// x < 0: the point stands in the margin on the left, level with the row — it covers no text.
struct Crop {
    let rect: CGRect
    let points: [CGPoint?]
}

/// Measured on `--export-help`.
enum HelpCrops {
    private static func m(_ y: CGFloat) -> CGPoint { CGPoint(x: -1, y: y) }
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// Points under the header buttons, not on them: the buttons are small and a point would cover them.
    static let panel = Crop(rect: CGRect(origin: .zero, size: HelpPictures.panelSize),
                            points: [p(254, 46), p(289, 46), m(110), m(430)])
    /// The first card with a strip above it: the points stand over its top row, not on it.
    static let card = Crop(rect: CGRect(x: 0, y: 40, width: 320, height: 140),
                           points: [p(75, 12), p(200, 12), p(290, 12), m(65)])
    static let states = Crop(rect: CGRect(x: 0, y: 50, width: 320, height: 345),
                             points: [m(55), m(188), m(286)])
    /// Step 1 is the Reset button on the card, which this popover does not show: no point for it.
    static func entry(_ size: NSSize) -> Crop {
        Crop(rect: CGRect(origin: .zero, size: size), points: [nil, m(52), m(80), p(125, 108)])
    }
    static func weekly(_ size: NSSize) -> Crop {
        Crop(rect: CGRect(origin: .zero, size: size), points: [nil, m(52), m(80)])
    }
    /// Settings down to the Macs list; the update check below shows the real date of the last check.
    static func macs(_ size: NSSize) -> Crop {
        Crop(rect: CGRect(x: 0, y: 0, width: size.width, height: min(size.height, 198)), points: [m(108)])
    }
}

/// A window picture in a section: the cut-out, its frame and the numbered points.
/// Never enlarged beyond 1:1 — bigger than the window it would look like a screenshot under a magnifier.
struct WindowPicture: View {
    let image: NSImage
    let crop: Crop
    var maxWidth: CGFloat = 440
    private let margin: CGFloat = 36

    var body: some View {
        let r = crop.rect
        let left: CGFloat = crop.points.contains { ($0?.x ?? 0) < 0 } ? margin : 0
        let w = min(maxWidth - left, r.width)
        let scale = w / r.width
        let h = r.height * scale
        Frame {
            HStack(spacing: 0) {
                Color.clear.frame(width: left, height: h)
                Image(nsImage: image.cutOut(r)).resizable().interpolation(.high).frame(width: w, height: h)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(crop.points.enumerated()), id: \.offset) { i, p in
                        if let p {
                            Marker(number: i + 1).position(x: p.x < 0 ? margin / 2 + 2 : left + p.x * scale, y: p.y * scale)
                        }
                    }
                }
                .frame(width: left + w, height: h, alignment: .topLeading)
            }
        }
    }
}

/// The numbered point on a picture, and the same number in front of a step.
struct Marker: View {
    let number: Int
    var small = false

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.system(size: small ? 11 : 13, weight: .bold)).monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: small ? 20 : 26, height: small ? 20 : 26)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(.white, lineWidth: small ? 0 : 2))
            .shadow(color: .black.opacity(small ? 0 : 0.35), radius: 3, y: 1)
    }
}

/// Rounded card with a soft shadow — the frame every picture sits in.
struct Frame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

/// The Fractal 8 Dev signature at the end of Help, set like the hero of fractal8.eu: the logo large behind,
/// under the same veil as the site's video (darker at the edges and towards the bottom), and the text over
/// its lower part — "ENDLESS RECURSION" spaced 0.42 em in the accent (#7ee8f2 dark, #0a8796 light), then
/// "Fractal 8 Dev" in SF Pro Bold drawn together by −0.045 em with the site's gradient, then the site's line.
private struct FractalSignature: View {
    @Environment(\.colorScheme) private var scheme
    private static let logo: NSImage? = Bundle.main.url(forResource: "studio-logo", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        let dark = scheme == .dark
        let back = Color(nsColor: .windowBackgroundColor)
        let accent = dark ? Color(red: 126 / 255, green: 232 / 255, blue: 242 / 255) : Color(red: 10 / 255, green: 135 / 255, blue: 150 / 255)
        let gradient = LinearGradient(stops: [
            .init(color: dark ? .white : Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255), location: 0.4),
            .init(color: dark ? Color(red: 159 / 255, green: 163 / 255, blue: 171 / 255) : Color(red: 91 / 255, green: 95 / 255, blue: 102 / 255), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        ZStack(alignment: .bottom) {
            if let logo = Self.logo {
                Image(nsImage: logo).resizable().interpolation(.high).frame(width: 560, height: 560)
                    .opacity(dark ? 0.75 : 0.55)
                    .frame(height: 440, alignment: .top)
                    .clipped()
                    // The site's veil (styles.css, .hero-sticky::after): edges and the bottom sink into the background.
                    .overlay(RadialGradient(stops: [.init(color: .clear, location: 0.35), .init(color: back.opacity(0.75), location: 1)],
                                            center: .center, startRadius: 0, endRadius: 300))
                    .overlay(LinearGradient(stops: [.init(color: back.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                                    .init(color: back.opacity(0.55), location: 0.62), .init(color: back, location: 0.92)],
                                            startPoint: .top, endPoint: .bottom))
            }
            VStack(spacing: 0) {
                Text(verbatim: "ENDLESS RECURSION")
                    .font(.system(size: 12)).tracking(12 * 0.42).foregroundStyle(accent)
                    .padding(.bottom, 16)
                Text(verbatim: "Fractal 8 Dev")
                    .font(.system(size: 76, weight: .bold)).tracking(-76 * 0.045)
                    .foregroundStyle(gradient)
                Text(verbatim: HelpContent.signatureLine.current)
                    .font(.system(size: 17)).foregroundStyle(.secondary)
                    .padding(.top, 18)
            }
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 440)
        .padding(.top, 40)
    }
}

// MARK: - Bitmap of the Help page, for checking it without opening a window

/// `TokenTime --export-help <folder> -TokenTime_Language pl|en`: draws the Help page and the pictures into PNG
/// files and quits, from `TokenTimeApp.init` — before the menu bar item appears. `--export-help-window <folder>`:
/// the Help window as the app shows it, to check what the user sees, not only the export.
enum HelpExport {
    static var requested: Bool {
        CommandLine.arguments.contains("--export-help") || CommandLine.arguments.contains("--export-help-window")
    }

    static func runIfRequested() {
        let a = CommandLine.arguments
        MainActor.assumeIsolated {
            let lang = loc.language.rawValue
            if let i = a.firstIndex(of: "--export-help-window"), i + 1 < a.count {
                NSApplication.shared.setActivationPolicy(.prohibited)
                let folder = URL(fileURLWithPath: a[i + 1], isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let size = NSSize(width: HelpPage.width, height: 900)
                let host = NSHostingView(rootView: HelpPage(pictures: HelpPictures.make()))
                let w = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
                w.isReleasedWhenClosed = false
                host.frame = NSRect(origin: .zero, size: size)
                w.contentView = host
                w.orderFrontRegardless()
                RunLoop.current.run(until: Date().addingTimeInterval(2))
                save(Render.bitmap(host), folder.appendingPathComponent("help-window-\(lang).png"))
                exit(0)
            }
            guard let i = a.firstIndex(of: "--export-help"), i + 1 < a.count else { return }
            let folder = URL(fileURLWithPath: a[i + 1], isDirectory: true)
            NSApplication.shared.setActivationPolicy(.prohibited)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let p = HelpPictures.make()
            for (name, image) in [("label", p.label), ("panel", p.panel), ("entry", p.entry), ("weekly", p.weekly), ("settings", p.settings)] {
                save(image, folder.appendingPathComponent("window-\(name)-\(lang).png"))
            }
            let page = HelpPage(pictures: p, wholePage: true)
            // The height measured at the fixed width — `fittingSize` measures without it and cuts the top and bottom off.
            let h = NSHostingController(rootView: page)
                .sizeThatFits(in: CGSize(width: HelpPage.width, height: CGFloat.greatestFiniteMagnitude)).height
            save(Render.window(page, size: NSSize(width: HelpPage.width, height: ceil(h)), titled: false, title: "", settle: 0.3),
                 folder.appendingPathComponent("help-\(lang).png"))
            exit(0)
        }
    }

    private static func save(_ image: NSImage, _ url: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        FileHandle.standardOutput.write(Data("\(url.path) \(Int(image.size.width))×\(Int(image.size.height))\n".utf8))
    }
}
