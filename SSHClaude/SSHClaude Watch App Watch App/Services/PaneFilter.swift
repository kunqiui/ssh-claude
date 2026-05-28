import Foundation

/// 把 tmux capture-pane 的原始文本清洗成 Watch 上要展示的行。
///
/// Claude Code TUI 输出里有大量装饰性内容（banner、状态栏、思考动画），
/// 在小屏上没有任何价值，把它们全过滤掉，让用户只看到真正的对话内容。
enum PaneFilter {
    /// 入口：原始 pane 文本 → 过滤后的最近 N 行。
    /// - Parameters:
    ///   - raw: tmux capture-pane 抓到的多行字符串（已经 strip 过 ANSI）
    ///   - tailing: 最多保留的行数（取最后 N 行）
    static func clean(_ raw: String, tailing: Int = 40) -> [String] {
        let kept: [String] = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(shouldKeep)
        return Array(kept.suffix(tailing))
    }

    // MARK: - 单行判定

    private static func shouldKeep(_ line: String) -> Bool {
        if line.isEmpty { return false }
        if isSeparator(line) { return false }
        if isBannerBox(line) { return false }
        if isBannerText(line) { return false }
        if isBottomStatus(line) { return false }
        if isThinkingAnimation(line) { return false }
        return true
    }

    /// 纯下划线 / 横线 / 等号组成的分隔行（"___" "────" "===" 等）。
    private static func isSeparator(_ line: String) -> Bool {
        let stripped = line
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "─", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty
    }

    /// Claude TUI banner 的边框（box-drawing 字符）。
    private static func isBannerBox(_ line: String) -> Bool {
        line.contains(where: { c in
            c == "╭" || c == "╮" || c == "╰" || c == "╯" || c == "│"
        })
    }

    /// banner 内的固定文案（即使脱掉边框也是噪音）。
    private static func isBannerText(_ line: String) -> Bool {
        let lower = line.lowercased()
        return bannerPhrases.contains(where: { lower.contains($0) })
    }

    private static let bannerPhrases = [
        "welcome back", "tips for getting", "what's new",
        "claude code v", "release-notes", "skills and slash",
        "ask claude to", "code-review", "reload-skills",
        "opus 4.7", "api usage billing", "1m context",
    ]

    /// 底部状态栏 / 思考耗时提示。
    private static func isBottomStatus(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("tip:") { return true }
        if lower.contains("for shortcuts") { return true }
        if lower.hasPrefix("?") && lower.contains("shortcut") { return true }
        if lower.contains("bypass permissions") { return true }
        if lower.contains("shift+tab") { return true }
        if lower.contains("for agents") { return true }
        if lower.hasPrefix("brewed for") { return true }
        if lower.hasPrefix("churned for") { return true }
        if lower.hasPrefix("thought for") { return true }
        if lower.hasPrefix("thinking for") { return true }
        if lower.hasPrefix("baked for") { return true }
        return false
    }

    /// Claude 思考状态行：· ✢ ✳ ✶ ✻ ✽ 这些字符开头（呼吸动画）。
    private static func isThinkingAnimation(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return thinkingPrefixChars.contains(first)
    }

    private static let thinkingPrefixChars: Set<Character> = ["·", "✢", "✳", "✶", "✻", "✽"]
}
