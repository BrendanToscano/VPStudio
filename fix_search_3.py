import re

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "r") as f:
    grid = f.read()

# Increase minimum width further to force a 2-row layout within the container
grid = re.sub(r'private let columns = \[GridItem\(\.adaptive\(minimum: 180, maximum: 240\), spacing: 20\)\]',
              r'private let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 16)]', grid)

# Slightly reduce height so the aspect ratio feels like the reference image (slightly rectangular, wide)
grid = re.sub(r'\.frame\(height: 140\)',
              r'.frame(height: 120)', grid)

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write(grid)


with open("VPStudio/Views/Windows/Search/SearchView.swift", "r") as f:
    sv = f.read()

# The container is probably too wide or narrow. Let's make it exactly fit 7 columns if each is 190 + 16 spacing = ~1442
# If we want 7 columns, 14 items total = 2 rows.
sv = re.sub(r'private let contentMaxWidth: CGFloat = 1360',
            r'private let contentMaxWidth: CGFloat = 1450', sv)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "w") as f:
    f.write(sv)
