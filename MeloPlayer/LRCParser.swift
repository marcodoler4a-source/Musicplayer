import Foundation

struct LRCLine: Hashable {
    let time: TimeInterval
    let text: String
}

enum LRCParser {
    // Supports [mm:ss], [mm:ss.xx], [mm:ss.xxx] and multiple timestamps on one line.
    static func parse(_ source: String) -> [LRCLine] {
        var output: [LRCLine] = []
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for raw in source.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            var lyric = regex.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: "").trimmingCharacters(in: .whitespaces)
            if lyric.hasPrefix("[") && lyric.hasSuffix("]") { lyric = "" } // metadata-only line
            for m in matches {
                guard m.numberOfRanges >= 3 else { continue }
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var fraction = 0.0
                if m.numberOfRanges > 3, m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    fraction = (Double(f) ?? 0) / pow(10.0, Double(f.count))
                }
                output.append(LRCLine(time: min * 60 + sec + fraction, text: lyric))
            }
        }
        return output.sorted { $0.time < $1.time }
    }

    static func activeIndex(in lines: [LRCLine], at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result: Int?
        for (i, line) in lines.enumerated() {
            if line.time <= time + 0.05 { result = i } else { break }
        }
        return result
    }

    static func plainText(from source: String) -> String {
        let pattern = #"\[[^\]]+\]"#
        return source.components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
