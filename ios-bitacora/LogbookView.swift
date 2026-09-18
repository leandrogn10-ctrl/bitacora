/*  LogbookView.swift — the app's one surface: Bitácora's real engine in a WKWebView, plus the
    native things a web page cannot do for itself.

    WHY A CUSTOM SCHEME AND NOT loadFileURL. The logbook lives in localStorage, so the ORIGIN is
    load-bearing: it is the key the data is filed under. A file:// origin is the odd child in
    every WebKit storage migration, and a 127.0.0.1 server would tie the library to a port
    number (a different port is a different origin, and the data is simply gone). A registered
    scheme handler gives a stable, port-free origin in the ordinary website data store — the
    same reason Capacitor and Ionic both moved off local HTTP servers onto one.

    The webview holds NO credentials of its own. Bitácora's GitHub/Anthropic keys live where
    they always did, inside the app's own settings in localStorage. */
import SwiftUI
import WebKit
import UIKit

// MARK: - Serving the bundle

/// Serves bitacora-app://local/… out of the app bundle's Resources/app folder.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "bitacora-app"
    static let root = "local"

    private static let types: [String: String] = [
        "html": "text/html; charset=utf-8",
        "js":   "text/javascript; charset=utf-8",
        "css":  "text/css; charset=utf-8",
        "ttf":  "font/ttf",
        "json": "application/json; charset=utf-8",
        "svg":  "image/svg+xml",
        "png":  "image/png",
    ]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = "index.html" }

        // Containment: a served path may never climb out of the bundled app directory.
        guard !path.contains("..'"), !path.contains(".."),
              let base = Bundle.main.url(forResource: "app", withExtension: nil)
        else { return task.didFailWithError(URLError(.badURL)) }

        let file = base.appendingPathComponent(path)
        guard file.path.hasPrefix(base.path), let data = try? Data(contentsOf: file) else {
            // A 404 that says WHICH path is missing — a blank screen has too many causes to
            // debug from the outside, and this is the cheapest instrument that tells them apart.
            Vault.shared.log("404 \(path)")
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1",
                                    headerFields: ["Content-Type": "text/plain"])!
            task.didReceive(r); task.didReceive(Data("not in bundle: \(path)".utf8)); task.didFinish()
            return
        }
        let mime = Self.types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime,
                                                  "Cache-Control": "no-cache"])!
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - The bridge

final class Bridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let selection = UISelectionFeedbackGenerator()
    private let notice = UINotificationFeedbackGenerator()

    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let body = m.body as? [String: Any], let cmd = body["cmd"] as? String else { return }
        switch cmd {
        case "save":    handleSave(body["json"] as? String)
        case "haptic":  handleHaptic(body["kind"] as? String ?? "light")
        case "share":   handleShare(body)
        case "ready":   Vault.shared.log("page ready")
        case "log":     Vault.shared.log("page: \(body["text"] as? String ?? "")")
        default: break
        }
    }

    // MARK: saves

    private func handleSave(_ json: String?) {
        guard let json, let data = json.data(using: .utf8) else { return }
        let verdict = Vault.shared.offer(data)
        switch verdict {
        case .accepted:
            break                                    // the quiet, overwhelmingly common case
        case .heldStale:
            break                                    // a late duplicate; nothing a human must act on
        case .heldShrink(let was, let now):
            notice.notificationOccurred(.warning)
            toPage("shrink", "\(was) titles to \(now)")
            askAboutShrink(was: was, now: now)
        case .rejectedInvalid:
            notice.notificationOccurred(.error)
            toPage("invalid", "")
        }
    }

    private func toPage(_ kind: String, _ detail: String) {
        let esc = detail.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("window.__bitacoraVaultNotice && window.__bitacoraVaultNotice('\(kind)','\(esc)')")
    }

    /// A held save is a question, and a question needs a human. Presented natively so it
    /// cannot be missed behind a toast — and phrased so that doing nothing is the safe outcome.
    private func askAboutShrink(was: Int, now: Int) {
        guard let vc = Self.topViewController() else { return }
        if vc is UIAlertController { return }        // don't stack one per keystroke-save
        let a = UIAlertController(
            title: "Backup held",
            message: "This save drops your library from \(was) titles to \(now). Your backup still has all \(was).\n\nIf you meant to delete them, keep the change. If not, the backup is untouched — reopen the app to restore it.",
            preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Keep backup", style: .cancel))
        a.addAction(UIAlertAction(title: "I deleted them", style: .destructive) { _ in
            _ = Vault.shared.promotePending()
        })
        vc.present(a, animated: true)
    }

    // MARK: haptics

    private func handleHaptic(_ kind: String) {
        switch kind {
        case "selection": selection.selectionChanged()
        case "medium":    medium.impactOccurred()
        case "success":   notice.notificationOccurred(.success)
        case "warning":   notice.notificationOccurred(.warning)
        default:          light.impactOccurred()
        }
    }

    // MARK: share

    /// WKWebView ships no Web Share API, so phone-boot-pre.js shims navigator.share onto this.
    private func handleShare(_ body: [String: Any]) {
        let id = body["id"] as? Int ?? 0
        let title = body["title"] as? String ?? ""
        let text = body["text"] as? String ?? ""
        var items: [Any] = [text.isEmpty ? title : text]
        if let s = body["url"] as? String, let u = URL(string: s), !s.isEmpty { items.append(u) }

        guard let vc = Self.topViewController() else { return resolveShare(id, false, "no presenter") }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        av.completionWithItemsHandler = { [weak self] _, done, _, err in
            self?.resolveShare(id, done, err?.localizedDescription ?? "dismissed")
        }
        // iPad/Catalyst would crash without an anchor; harmless on iPhone.
        av.popoverPresentationController?.sourceView = vc.view
        av.popoverPresentationController?.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.maxY, width: 0, height: 0)
        vc.present(av, animated: true)
    }

    private func resolveShare(_ id: Int, _ ok: Bool, _ why: String) {
        let esc = why.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("window.__bitacoraShareResult && window.__bitacoraShareResult(\(id), \(ok), '\(esc)')")
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

// MARK: - The view

struct LogbookView: UIViewRepresentable {
    func makeCoordinator() -> Bridge { Bridge() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: BundleSchemeHandler.scheme)
        cfg.websiteDataStore = .default()          // persistent; NOT .nonPersistent()
        cfg.allowsInlineMediaPlayback = true

        /*  The vault, injected synchronously at document-start — it MUST be in place before
            index.html's own script reads localStorage, so this cannot be a fetch.
            Base64 with an explicit UTF-8 decode, NOT JSON.parse(atob(...)): atob yields bytes,
            and reading them as characters mangles every accented title in the library — which
            in a library of Spanish and Latin American titles is most of them. */
        if let json = Vault.shared.primaryJSON(),
           let b64 = json.data(using: .utf8)?.base64EncodedString() {
            let s = Vault.shared.currentSummary()
            let src = """
            (function () {
              try {
                var bin = atob('\(b64)');
                var bytes = new Uint8Array(bin.length);
                for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
                window.__BITACORA_VAULT__ = {
                  json: new TextDecoder('utf-8').decode(bytes),
                  lastModified: \(Int(s?.lastModified ?? 0)),
                  items: \(s?.itemCount ?? 0)
                };
              } catch (e) { window.__BITACORA_VAULT__ = null; }
            })();
            """
            cfg.userContentController.addUserScript(
                WKUserScript(source: src, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        cfg.userContentController.add(context.coordinator, name: "bitacora")

        let wv = WKWebView(frame: .zero, configuration: cfg)
        context.coordinator.webView = wv
        wv.scrollView.contentInsetAdjustmentBehavior = .never   // the page positions itself from env(safe-area-*)
        wv.scrollView.bounces = false
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.086, green: 0.031, blue: 0.063, alpha: 1)  // --bg #160810
        wv.scrollView.backgroundColor = .clear
        #if DEBUG
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        #endif

        let url = URL(string: "\(BundleSchemeHandler.scheme)://\(BundleSchemeHandler.root)/index.html")!
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
