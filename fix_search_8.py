import re

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "r") as f:
    grid = f.read()

grid = re.sub(r'private let columns = Array\(repeating: GridItem\(\.flexible\(minimum: 150, maximum: 240\), spacing: 16\), count: 7\)',
              r'private let columns = Array(repeating: GridItem(.fixed(160), spacing: 16), count: 7)', grid)

grid = re.sub(r'\.aspectRatio\(1\.0, contentMode: \.fit\)',
              r'.frame(height: 160)', grid)

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write(grid)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "r") as f:
    sv = f.read()

# Make sure it can fit 7 * 160 + 6 * 16 = 1120 + 96 = 1216 width container. 
sv = re.sub(r'private let contentMaxWidth: CGFloat = 1600',
            r'private let contentMaxWidth: CGFloat = 1250', sv)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "w") as f:
    f.write(sv)
