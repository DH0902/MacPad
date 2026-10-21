import AppKit
import MacPadCore

/// Tools menu actions. They live on the document so they're only enabled when an editor window is in front.
extension TextDocument {
    private var name: String { displayName ?? "Untitled" }

    @objc func lintCSV(_ sender: Any?) {
        CSVLintPanel.shared.lint(self)
    }

    /// Sent by the dynamic "Compare With" submenu; the other document is the item's `representedObject`.
    @objc func compareWithDocument(_ sender: Any?) {
        guard let other = (sender as? NSMenuItem)?.representedObject as? TextDocument else { return }
        CompareWindow.show(left: .init(name: name, text: text), right: .init(name: other.name, text: other.text))
    }

    @objc func compareWithFile(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose a file to compare with \(name)"
        panel.prompt = "Compare"
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            compare(withFileAt: url, fileLabel: url.lastPathComponent, savedOnLeft: false)
        }
    }

    @objc func compareWithSavedVersion(_ sender: Any?) {
        guard let url = fileURL else { return }
        compare(withFileAt: url, fileLabel: "\(name) (saved)", savedOnLeft: true)
    }

    private func compare(withFileAt url: URL, fileLabel: String, savedOnLeft: Bool) {
        let current = CompareWindow.Side(name: savedOnLeft ? "\(name) (current)" : name, text: text)
        Task {
            do {
                let fileText = try await inBackground { try TextFileCodec.read(contentsOf: url).text }
                let file = CompareWindow.Side(name: fileLabel, text: fileText)
                CompareWindow.show(left: savedOnLeft ? file : current, right: savedOnLeft ? current : file)
            } catch {
                presentError(error)
            }
        }
    }
}
