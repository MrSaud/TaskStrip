import Foundation

/// Fractional sort keys: strings that sort in the board's order, where a key can always be made
/// between any two others. Moving one strip gives it one new key and leaves every other strip's
/// key alone — so two devices reordering at once each change only the strips they moved, instead
/// of renumbering the whole board and scrambling each other.
///
/// Digits are base 62 in ASCII order (0–9, A–Z, a–z), so plain string comparison is the order.
/// A key never ends in "0", which is what guarantees there's always room between two keys.
enum SortKey {
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let base = 62
    private static let index: [Character: Int] = Dictionary(uniqueKeysWithValues: digits.enumerated().map { ($1, $0) })

    /// A key strictly between `lower` and `upper`; nil means the start or the end of the board.
    static func between(_ lower: String?, _ upper: String?) -> String {
        let lo = Array(lower ?? "")
        var hi: [Character]? = upper.map(Array.init)
        var result: [Character] = []
        var position = 0
        while true {
            let low = position < lo.count ? index[lo[position]] ?? 0 : 0
            let high = hi.map { position < $0.count ? index[$0[position]] ?? 0 : 0 } ?? base
            if high - low > 1 {
                result.append(digits[(low + high) / 2])
                return String(result)
            }
            result.append(digits[low])
            // Once the upper bound is one digit ahead, anything after this digit stays below it.
            if high - low == 1 { hi = nil }
            position += 1
        }
    }

    /// `count` keys between `lower` and `upper`, spread by halving so none grows long.
    static func spread(_ count: Int, between lower: String?, _ upper: String?) -> [String] {
        guard count > 0 else { return [] }
        let middle = between(lower, upper)
        let before = count / 2
        return spread(before, between: lower, middle) + [middle] + spread(count - before - 1, between: middle, upper)
    }

    /// New keys for the strips whose key is missing or out of order, given every strip in board
    /// order with the key it has now ("" for none).
    ///
    /// Keeps the longest run of keys that are already in order — so a single move rewrites one
    /// key, not the board — and fits the rest between their kept neighbours. Two strips given the
    /// same key by two devices at once aren't both kept: one of them is re-keyed.
    static func rekey(_ ordered: [(id: String, key: String)]) -> [String: String] {
        let kept = longestIncreasingRun(ordered.map(\.key))
        var changes: [String: String] = [:]
        var pending: [Int] = []
        var lowerKey: String?

        func flush(upTo upperKey: String?) {
            let keys = spread(pending.count, between: lowerKey, upperKey)
            for (slot, key) in zip(pending, keys) { changes[ordered[slot].id] = key }
            pending.removeAll()
        }

        for (slot, item) in ordered.enumerated() {
            if kept.contains(slot) {
                flush(upTo: item.key)
                lowerKey = item.key
            } else {
                pending.append(slot)
            }
        }
        flush(upTo: nil)
        return changes
    }

    /// Positions forming the longest strictly increasing run of non-empty keys.
    private static func longestIncreasingRun(_ keys: [String]) -> Set<Int> {
        var tails: [Int] = []          // slot of the smallest tail for each run length
        var previous = [Int](repeating: -1, count: keys.count)
        for (slot, key) in keys.enumerated() where !key.isEmpty {
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if keys[tails[mid]] < key { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { previous[slot] = tails[lo - 1] }
            if lo == tails.count { tails.append(slot) } else { tails[lo] = slot }
        }
        var run = Set<Int>()
        var slot = tails.last ?? -1
        while slot >= 0 {
            run.insert(slot)
            slot = previous[slot]
        }
        return run
    }
}
