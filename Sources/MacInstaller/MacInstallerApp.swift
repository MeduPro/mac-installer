import AppKit
import SwiftUI

@main
struct MacInstallerApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = InstallerModel()

    var body: some Scene {
        Window("MeduPro Mac-Installer", id: "main") {
            RootView()
                .environment(model)
                .tint(.brand)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("Über MeduPro Mac-Installer") { AppDelegate.showAboutPanel() }
            }
            CommandGroup(replacing: .help) {
                Link("medupro.de", destination: Brand.website)
                Link("Support per E-Mail", destination: Brand.supportMail())
            }
        }
    }
}

/// Herausgeber der App.
enum Brand {
    static let publisher = "MeduPro"
    static let website = URL(string: "https://medupro.de")!
    static let supportAddress = "support@medupro.de"

    /// mailto-Link, optional mit vorbereitetem Betreff und Text.
    static func supportMail(subject: String = "MeduPro Mac-Installer", body: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = supportAddress
        c.queryItems = [URLQueryItem(name: "subject", value: subject)]
            + (body.map { [URLQueryItem(name: "body", value: $0)] } ?? [])
        return c.url!
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Beim Start ohne Bundle (swift run) wäre die App sonst nur ein Hintergrundprozess.
        NSApp.setActivationPolicy(.regular)
        // Für Bildschirmfotos: MACINSTALLER_APPEARANCE=dark|light erzwingt das Erscheinungsbild.
        switch ProcessInfo.processInfo.environment["MACINSTALLER_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor static func showAboutPanel() {
        let text = NSMutableAttributedString(
            string: "Installiert tomedo® und Arzeko direkt vom eigenen tomedo-Server.\n\n"
                + "Ein kostenloses Angebot von \(Brand.publisher)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        )
        text.append(NSAttributedString(string: "medupro.de", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: Brand.website]))
        text.append(NSAttributedString(string: "  ·  ", attributes: [.font: NSFont.systemFont(ofSize: 11)]))
        text.append(NSAttributedString(string: Brand.supportAddress, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .link: Brand.supportMail()]))
        text.append(NSAttributedString(
            string: "\n\ntomedo® ist eine Marke der zollsoft GmbH. Der MeduPro Mac-Installer ist ein unabhängiges "
                + "Projekt und steht in keiner Verbindung zur zollsoft GmbH.",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        text.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: text.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: text])
        NSApp.activate()
    }
}

extension Color {
    /// Akzentfarbe: MeduPro-Violett #7038d8, im dunklen Erscheinungsbild heller (#a98bff), damit
    /// Text darauf lesbar bleibt.
    static let brand = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0xA9 / 255, green: 0x8B / 255, blue: 0xFF / 255, alpha: 1)
            : NSColor(srgbRed: 0x70 / 255, green: 0x38 / 255, blue: 0xD8 / 255, alpha: 1)
    })
    /// Fläche des Hauptknopfs: immer #7038d8, weißer Text darauf bleibt in beiden Modi lesbar.
    static let brandFill = Color(red: 0x70 / 255, green: 0x38 / 255, blue: 0xD8 / 255)
}
