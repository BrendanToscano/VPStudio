import Testing
@testable import VPStudio

@Suite("Library Sort Policy")
struct LibrarySortPolicyTests {

    @Test
    func allCasesAreIterable() {
        #expect(LibrarySortOption.allCases.count == 6)
    }

    @Test
    func defaultSortIsDateAddedDesc() {
        let defaultSort: LibrarySortOption = .dateAddedDesc
        #expect(defaultSort == .dateAddedDesc)
        #expect(defaultSort.displayName == "Recently Added")
    }

    @Test(arguments: LibrarySortOption.allCases)
    func displayNameIsNotEmpty(option: LibrarySortOption) {
        #expect(!option.displayName.isEmpty)
    }

    @Test(arguments: LibrarySortOption.allCases)
    func symbolNameIsNotEmpty(option: LibrarySortOption) {
        #expect(!option.symbolName.isEmpty)
    }

    @Test
    func rawValuesAreUnique() {
        let rawValues = LibrarySortOption.allCases.map(\.rawValue)
        #expect(Set(rawValues).count == rawValues.count)
    }

    @Test
    func displayNamesAreUnique() {
        let names = LibrarySortOption.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    @Test
    func dateAddedDescDisplayName() {
        #expect(LibrarySortOption.dateAddedDesc.displayName == "Recently Added")
    }

    @Test
    func dateAddedAscDisplayName() {
        #expect(LibrarySortOption.dateAddedAsc.displayName == "Oldest Added")
    }

    @Test
    func titleAscDisplayName() {
        #expect(LibrarySortOption.titleAsc.displayName.contains("A"))
        #expect(LibrarySortOption.titleAsc.displayName.contains("Z"))
    }

    @Test
    func titleDescDisplayName() {
        #expect(LibrarySortOption.titleDesc.displayName.contains("Z"))
        #expect(LibrarySortOption.titleDesc.displayName.contains("A"))
    }

    @Test
    func yearDescDisplayName() {
        #expect(LibrarySortOption.yearDesc.displayName == "Newest Release")
    }

    @Test
    func yearAscDisplayName() {
        #expect(LibrarySortOption.yearAsc.displayName == "Oldest Release")
    }

    @Test
    func conformsToHashable() {
        let set: Set<LibrarySortOption> = [.dateAddedDesc, .titleAsc, .dateAddedDesc]
        #expect(set.count == 2)
    }

    @Test
    func conformsToSendable() {
        let option: LibrarySortOption = .yearDesc
        Task {
            let _ = option.displayName
        }
    }
}
