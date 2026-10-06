Duck Pond sugar maples for Roblox -- first batch (2026-10-06)

FILES
  sugar_maple_1 .. sugar_maple_5        standard, 1,900-1,925 triangles each
  sugar_maple_1_hero .. _5_hero         hero,     4,656-4,792 triangles each
  Each comes as .obj (+ .mtl) and .fbx -- the same geometry. Each holds three meshes:
    Trunk     (collide this)
    Branches
    Leaves    (leaf cards, no collision)
  textures/  shared by all ten files, 1024 x 1024 PNG:
    sugar_maple_bark_color.png
    sugar_maple_bark_normal.png     tangent-space, OpenGL (green up), as Roblox expects
    sugar_maple_leaves_color.png    RGBA, the cut-out is in its alpha channel
    sugar_maple_leaves_alpha.png    the same alpha on its own, greyscale
  sugar_maple_trees.csv  file -> tree ID, species, position, size, triangle counts

YOUR QUESTIONS
1. Back faces: the leaf cards already have them, and they are counted in the triangle totals
   above. Please leave DoubleSided off, or the leaves will be doubled a second time.
2. Textures: 1024 x 1024 PNGs. The leaf alpha is in the colour PNG and also as a separate PNG.
   Leaves are slightly desaturated (25% toward grey) so you can tint them. For leaves, use
   AlphaMode = Transparency.
3. Units are studs, 1 stud = 0.28 m. Y is up, and the pivot (origin) is at the base of the
   trunk. Keep the importer's Scale Unit on Studs. The models are already at each tree's real
   size, so they don't need rescaling. On the three smaller trees, leaf cards stick out up to
   about 4 studs above the inventory height (compare inventory_height_studs and model_height_studs in
   the CSV).
4. Tree IDs: see sugar_maple_trees.csv. Species, latitude/longitude, height and trunk diameter
   are the real Duck Pond inventory trees. The branch shape, though, is NOT a scan of that exact
   tree. It is a real maple scan from TreeML-Data (Munich street trees; the scan ID is in the
   CSV), sized and posed to match the inventory tree. Note that ACSA2-4511 is about 500 m
   northeast of the other four, so check that it falls inside your map.

NORMAL MAP NOTE
Roblox needs tangents to use a normal map. OBJ cannot store them, but the FBX files do (and
are otherwise identical). If the bark normal map shows no effect on the OBJ version, use the
FBX.

CREDITS (please keep)
Tree shapes are derived from TreeML-Data, CC BY 4.0:
  Yazdi, H., Shu, Q., Rotzer, T., Petzold, F. & Ludwig, F. (2024). A multilayered urban tree
  dataset of point clouds, quantitative structure and graph models. Scientific Data 11, 28.
  https://doi.org/10.1038/s41597-023-02873-x
Textures are CC0 (no credit needed): ambientCG Bark001 and LeafSet027.
