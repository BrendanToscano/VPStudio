import re

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "r") as f:
    grid = f.read()

grid = re.sub(r'\.font\(\.system\(size: 20, weight: \.bold, design: \.rounded\)\)',
              r'.font(.system(size: 24, weight: .bold, design: .rounded))', grid)

grid = re.sub(r'\.font\(\.system\(size: 12, weight: \.heavy, design: \.rounded\)\)',
              r'.font(.system(size: 14, weight: .heavy, design: .rounded))', grid)

with open("VPStudio/Views/Windows/Search/ExploreGenreGrid.swift", "w") as f:
    f.write(grid)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "r") as f:
    sv = f.read()

sv = re.sub(r'\.font\(\.system\(size: 13, weight: \.medium, design: \.rounded\)\)',
            r'.font(.system(size: 18, weight: .medium, design: .rounded))', sv)

with open("VPStudio/Views/Windows/Search/SearchView.swift", "w") as f:
    f.write(sv)
