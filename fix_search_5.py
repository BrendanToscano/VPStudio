import re

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "r") as f:
    grid = f.read()

# Increase minimum width further to force exactly a 2-row layout within the container. 
# 14 cards total. 7 cards per row means columns need to be roughly 1520 / 7 = 217 width each.
grid = re.sub(r'private let columns = \[GridItem\(\.adaptive\(minimum: 200, maximum: 300\), spacing: 16\)\]',
              r'private let columns = [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 16)]', grid)

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write(grid)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "r") as f:
    sv = f.read()

# Increase width to perfectly hold 7 columns of 210 width + 16 spacing = 1582. Let's use 1600.
sv = re.sub(r'private let contentMaxWidth: CGFloat = 1520',
            r'private let contentMaxWidth: CGFloat = 1600', sv)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "w") as f:
    f.write(sv)
