# CC0 model kits

The furniture, clutter, board landmarks and miniatures come from free CC0 (public domain) packs.
CC0 asks for no credit, but these artists made the game look far better than we could by hand, so:
thank you, and please support them.

| Folder | Pack | Artist | Licence | Source |
|---|---|---|---|---|
| `fantasy_props/` | Fantasy Props MegaKit (Standard) | [Quaternius](https://quaternius.com) | CC0 1.0 (`License.txt`) | [Godot Asset Store](https://store.godotengine.org/asset/quaternius/fantasy-props-megakit/) |
| `nature/` | Stylized Nature MegaKit (Standard) | [Quaternius](https://quaternius.com) | CC0 1.0 (`License.txt`) | [Godot Asset Store](https://store.godotengine.org/asset/quaternius/stylized-nature-megakit/) |
| `hexagon/` | KayKit Medieval Hexagon Pack 1.0 | [Kay Lousberg](https://www.kaylousberg.com) | CC0 1.0 (`License.txt`) | [GitHub](https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0), [itch.io](https://kaylousberg.itch.io/kaykit-medieval-hexagon) |
| `minis/` | KayKit Character Pack: Adventurers 1.0 | [Kay Lousberg](https://www.kaylousberg.com) | CC0 1.0 (`License_adventurers.txt`) | [GitHub](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) |
| `minis/` | KayKit Character Pack: Skeletons 1.0 | [Kay Lousberg](https://www.kaylousberg.com) | CC0 1.0 (`License_skeletons.txt`) | [GitHub](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) |

## What is here, and how it got here

Only the pieces the game uses are copied in, and only their colour maps: our toon shader
(`scripts/kits.gd`) paints with the base colour alone, so normal, roughness and occlusion maps are left
out. The nature textures are shrunk to 512 px because they only ever appear on the tale board.

- `tools/vendor_kits.py` copies the props, nature and hexagon models from the downloaded packs
  (needs Python 3 and Pillow). Edit its lists to bring in more pieces.
- `tools/bake_minis.gd` poses the KayKit characters (Idle animation) and bakes each into one static
  mesh, `minis/<kind>.res`, so the figurines cost one draw call and carry no rig or animations.

  ```
  python3 tools/vendor_kits.py --props <Fantasy_Props_MegaKit> --nature <Stylized_Nature_MegaKit> --hexagon <KayKit-Medieval-Hexagon-Pack-1.0>
  godot --headless -s res://tools/bake_minis.gd -- --adventurers=<KayKit-Character-Pack-Adventures-1.0> --skeletons=<KayKit-Character-Pack-Skeletons-1.0>
  ```

Still made in code, on purpose: the dice, flames, fire and dust, the night window, the room shell, the
table and dice tray (the dice collide with them), the tale board's parchment, roads and fog, the jug,
boats, bells, the jetty, the wolf and Mother Kettle figurines, and the board tokens. Run the game with
`-- --kits=off` to see the all-code look the kits replaced.
