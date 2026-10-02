import Foundation

/// Resolves the vault's daily-note template the way Obsidian itself does,
/// so a note the app creates looks exactly like one QuickAdd or the daily
/// notes plugin would have made. Resolution order:
///
/// 1. The daily-notes core plugin config (`.obsidian/daily-notes.json`,
///    `template` key, extension optional).
/// 2. The first enabled QuickAdd capture choice that creates files from a
///    template (`.obsidian/plugins/quickadd/data.json`).
/// 3. Nothing — the caller falls back to a minimal section skeleton.
public enum DailyTemplate {

    /// The template's text, or nil when no configured template exists or is
    /// readable. An existing but empty template counts as empty text.
    public static func text(root: URL) -> String? {
        for relativePath in configuredPaths(root: root) {
            let normalized = relativePath.hasSuffix(".md") ? relativePath : relativePath + ".md"
            let url = root.appendingPathComponent(normalized)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    /// Template paths as configured, in priority order.
    public static func configuredPaths(root: URL) -> [String] {
        var paths: [String] = []

        let dailyNotesURL = root.appendingPathComponent(".obsidian/daily-notes.json")
        if let data = try? Data(contentsOf: dailyNotesURL),
            let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let template = config["template"] as? String, !template.isEmpty
        {
            paths.append(template)
        }

        let quickAddURL = root.appendingPathComponent(".obsidian/plugins/quickadd/data.json")
        if let data = try? Data(contentsOf: quickAddURL),
            let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = config["choices"] as? [[String: Any]]
        {
            for choice in choices {
                let create = choice["createFileIfItDoesntExist"] as? [String: Any] ?? [:]
                if create["enabled"] as? Bool == true, let template = create["template"] as? String,
                    !template.isEmpty
                {
                    paths.append(template)
                }
            }
        }
        return paths
    }
}
