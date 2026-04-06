import re

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "r") as f:
    grid = f.read()

# Increase minimum width further to force exactly a 2-row layout within the container
grid = re.sub(r'private let columns = \[GridItem\(\.adaptive\(minimum: 190, maximum: 280\), spacing: 16\)\]',
              r'private let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)]', grid)

# Slightly reduce height so the aspect ratio feels like the reference image (slightly rectangular, wide)
grid = re.sub(r'\.frame\(height: 120\)',
              r'.frame(height: 125)', grid)

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write(grid)


with open("VPStudio/Views/Windows/Search/SearchView.swift", "r") as f:
    sv = f.read()

# Increase width to perfectly hold 7 columns of 200 width + spacing (approx 1512)
sv = re.sub(r'private let contentMaxWidth: CGFloat = 1450',
            r'private let contentMaxWidth: CGFloat = 1520', sv)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "w") as f:
    f.write(sv)
