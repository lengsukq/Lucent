import Foundation

public enum PinyinHelper {
    private static let polyphoneReplacements: [(String, String)] = [
        ("音乐", "音悦"), ("乐器", "悦器"), ("快乐", "快悦"),
        ("调试", "条试"), ("调节", "条节"), ("调色", "条色"), ("调整", "条整"), ("调用", "掉用"),
        ("重庆", "虫庆"), ("重复", "虫复"), ("重启", "虫启"), ("重置", "虫置"), ("重装", "虫装"), ("重命名", "虫命名"),
        ("银行", "银航"), ("命令行", "命令航"), ("同行", "同航"), ("多行", "多航"), ("行号", "航号"),
        ("收藏", "收仓"), ("隐藏", "隐仓"), ("宝藏", "宝葬")
    ]

    public static func convert(_ text: String) -> (full: String, initials: String) {
        convertRaw(applyPolyphoneFixes(text))
    }

    public static func alternatePool(_ text: String) -> String {
        let raw = convertRaw(text)
        let fixed = convert(text)
        if raw == fixed { return "" }
        return "\(raw.full) \(raw.initials)"
    }

    /// Fast UTF-8 byte check for CJK Unified Ideographs so non-CJK strings skip CFStringTransform entirely.
    public static func containsCJK(_ text: String) -> Bool {
        for b in text.utf8 where b >= 0xE3 && b <= 0xE9 {
            return true
        }
        return false
    }

    /// Returns 2 for prefix match on full pinyin or initials, 1 for substring match, 0 if unmatched.
    public static func matchRank(asciiNeedle: String, in text: String) -> Int {
        guard asciiNeedle.count >= 2, containsCJK(text) else { return 0 }
        let (full, initials) = convert(text)
        if initials.hasPrefix(asciiNeedle) || full.hasPrefix(asciiNeedle) {
            return 2
        }
        if initials.contains(asciiNeedle) || full.contains(asciiNeedle) {
            return 1
        }
        let alt = alternatePool(text)
        if !alt.isEmpty && alt.contains(asciiNeedle) {
            return 1
        }
        return 0
    }

    private static func applyPolyphoneFixes(_ text: String) -> String {
        var out = text
        for (src, dst) in polyphoneReplacements where out.contains(src) {
            out = out.replacingOccurrences(of: src, with: dst)
        }
        return out
    }

    private static func convertRaw(_ text: String) -> (full: String, initials: String) {
        let stripped = text
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .lowercased() ?? text.lowercased()
        let tokens = stripped
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return (tokens.joined(), String(tokens.compactMap(\.first)))
    }
}
