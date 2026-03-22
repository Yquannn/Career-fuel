import Foundation

struct ComputationCache<Input: Hashable, Output> {
    private struct Entry {
        let input: Input
        let output: Output
    }

    private let capacity: Int
    private var entries: [Int: Entry] = [:]
    private var accessOrder: [Int] = []

    init(capacity: Int = 8) {
        self.capacity = max(capacity, 1)
    }

    func value(for input: Input) -> Output? {
        let key = cacheKey(for: input)
        guard let entry = entries[key], entry.input == input else { return nil }
        return entry.output
    }

    mutating func insert(_ output: Output, for input: Input) {
        let key = cacheKey(for: input)
        entries[key] = Entry(input: input, output: output)
        touch(key)
        trimIfNeeded()
    }

    mutating func removeAll() {
        entries.removeAll()
        accessOrder.removeAll()
    }

    private func cacheKey(for input: Input) -> Int {
        var hasher = Hasher()
        input.hash(into: &hasher)
        return hasher.finalize()
    }

    private mutating func touch(_ key: Int) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private mutating func trimIfNeeded() {
        while accessOrder.count > capacity, let oldestKey = accessOrder.first {
            accessOrder.removeFirst()
            entries.removeValue(forKey: oldestKey)
        }
    }
}
