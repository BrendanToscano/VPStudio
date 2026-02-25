import Foundation
import Testing

enum AssertionHelpers {
    static func expectSortedDescending<T: Comparable>(_ values: [T], _ message: String = "") {
        for index in 1..<values.count {
            let _ = message
            #expect(values[index - 1] >= values[index])
        }
    }

    static func expectUnique<T: Hashable>(_ values: [T], _ message: String = "") {
        let _ = message
        #expect(Set(values).count == values.count)
    }

    static func expectNonEmpty(_ value: String?, _ message: String = "") {
        let _ = message
        #expect(value?.isEmpty == false)
    }
}
