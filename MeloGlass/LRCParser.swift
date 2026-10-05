import Foundation
struct LRCParser {
 static func parse(_ text: String) -> [LyricLine] {
   let regex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#)
   var out:[LyricLine] = []
   for row in text.components(separatedBy: .newlines) {
     let ns=row as NSString; let matches=regex.matches(in: row, range:NSRange(location:0,length:ns.length));
     let lyric=regex.stringByReplacingMatches(in: row, range:NSRange(location:0,length:ns.length), withTemplate: "").trimmingCharacters(in:.whitespaces)
     for m in matches { let min=Double(ns.substring(with:m.range(at:1))) ?? 0; let sec=Double(ns.substring(with:m.range(at:2))) ?? 0; var frac=0.0; if m.range(at:3).location != NSNotFound { let s=ns.substring(with:m.range(at:3)); frac=(Double(s) ?? 0)/pow(10,Double(s.count)) }; out.append(.init(time:min*60+sec+frac,text:lyric)) }
   }
   return out.sorted{$0.time<$1.time}
 }
}
