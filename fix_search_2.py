import re
with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "r") as f:
    grid = f.read()

# Change from 7 columns to adaptive minimum 180 to form a nice 4-5 column 2-row grid.
# Make the frame height taller.
grid = re.sub(r'private let columns = Array\(repeating: GridItem\(\.flexible\(\), spacing: 16\), count: 7\)',
              r'private let columns = [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 20)]', grid)

grid = re.sub(r'\.aspectRatio\(1\.0, contentMode: \.fit\)',
              r'.frame(height: 140)', grid)

grid = re.sub(r'\.font\(\.system\(size: 32, weight: \.medium\)\)',
              r'.font(.system(size: 40, weight: .medium))', grid)

grid = re.sub(r'\.font\(\.system\(size: 17, weight: \.bold, design: \.rounded\)\)',
              r'.font(.system(size: 20, weight: .bold, design: .rounded))', grid)

grid = re.sub(r'\.font\(\.system\(size: 10, weight: \.heavy, design: \.rounded\)\)',
              r'.font(.system(size: 12, weight: .heavy, design: .rounded))', grid)

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write(grid)


with open("VPStudio/Views/Windows/Search/SearchView.swift", "r") as f:
    sv = f.read()

# Fix massive padding in idle content
sv = re.sub(r'\.padding\(\.horizontal, 40\)\n\s+\.padding\(\.top, 24\)\n\s+\.padding\(\.bottom, 48\)',
            r'.padding(.horizontal, 40)\n                .padding(.top, 12)\n                .padding(.bottom, 32)', sv)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "w") as f:
    f.write(sv)
