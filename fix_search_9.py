import re

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "r") as f:
    grid = f.read()

# Let's completely rewrite the Grid layout to guarantee 2 rows that scroll horizontally
# if that's what it takes to match "dense 2-row grid".
# Actually, the user's reference image shows 2 rows, 7 columns, all visible without scrolling.
# To make them square and fit exactly 7 columns in the container:
# Container width: 1250.
# 7 items * 160 width + 6 * 16 spacing = 1120 + 96 = 1216. This fits!
# But maybe we need to wrap LazyVGrid in an explicit padding or remove max width constraints.
# Let's adjust the minimum to 140, max 200, but keeping fixed(160) should work.
# Wait, maybe they are rendering as 3 rows because the container width is smaller than we think on device?
# Let's try `minimum: 120`.

grid = re.sub(r'private let columns = Array\(repeating: GridItem\(\.fixed\(160\), spacing: 16\), count: 7\)',
              r'private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 16)]', grid)

grid = re.sub(r'\.frame\(height: 160\)',
              r'.aspectRatio(1.0, contentMode: .fit)', grid)

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write(grid)

