import re

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "r") as f:
    grid = f.read()

# Make the frame height taller and the aspect ratio more square to push the third row out of view
# or make the cards wide enough to form a 2-row layout. Let's make columns much wider.
# 14 cards total. 7 cards per row = 2 rows. We need minimum width to be wider to force 7 items.
# Let's use fixed 7 columns explicitly instead of adaptive, but we already tried adaptive.
# Let's revert back to adaptive but minimum 220, max 300
grid = re.sub(r'private let columns = \[GridItem\(\.adaptive\(minimum: 210, maximum: 300\), spacing: 16\)\]',
              r'private let columns = Array(repeating: GridItem(.flexible(minimum: 150, maximum: 240), spacing: 16), count: 7)', grid)

grid = re.sub(r'\.frame\(height: 125\)',
              r'.aspectRatio(1.0, contentMode: .fit)', grid)

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write(grid)

