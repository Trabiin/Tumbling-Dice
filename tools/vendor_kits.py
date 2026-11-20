#!/usr/bin/env python3
"""Copy the CC0 kit models the game uses into assets/kits/: colour maps, plus normal maps for
the props kit (its carved panels, grooves and rivets live there; shrunk to 1024 px).

Our toon shader has no use for the ORM and occlusion maps, so each glTF is rewritten without
them, and only the textures still referenced are copied. This keeps the repository small.

  python3 -I tools/vendor_kits.py --props DIR --nature DIR --hexagon DIR

  --props    the Quaternius Fantasy Props MegaKit (Standard) folder that holds Exports/glTF
  --nature   the Quaternius Stylized Nature MegaKit (Standard) folder that holds glTF
  --hexagon  a clone of github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0

The KayKit characters are baked into posed meshes by tools/bake_minis.gd instead.
"""
import argparse
import json
import os
import shutil
import sys

PROPS = """Shelf_Small_Bottles Shelf_Simple Shelf_Arch Bottle_1 SmallBottles_1 Potion_1 Potion_2 Potion_4
Vase_2 Vase_4 Barrel Barrel_Holder Barrel_Apples Crate_Wooden Bag Lantern_Wall Chandelier Table_Large Stool
Chair_1 Bench Bookcase_2 Cabinet Workbench Workbench_Drawers Anvil Whetstone Peg_Rack Cauldron Bucket_Wooden_1
Mug Chalice Book_7 Book_5 Book_Stack_1 Book_Stack_2 BookGroup_Medium_1 BookGroup_Small_1 Coin Coin_Pile
Coin_Pile_2 Pouch_Large Candle_1 Candle_2 CandleStick CandleStick_Triple WeaponStand
Shield_Wooden Axe_Bronze Sword_Bronze Rope_1 Rope_2 Rope_3 Chain_Coil FarmCrate_Apple FarmCrate_Carrot Key_Gold Banner_1 Banner_2
Banner_1_Cloth Banner_2_Cloth Anvil_Log BookGroup_Medium_2 BookGroup_Small_2 Book_Simplified_Single Cage_Small Bucket_Metal
Table_Plate Pot_1 Pot_1_Lid Dummy""".split()

NATURE = """CommonTree_1 CommonTree_2 CommonTree_3 Pine_1 Pine_2 DeadTree_1 DeadTree_2 TwistedTree_1
Rock_Medium_1 Rock_Medium_2 Rock_Medium_3 Bush_Common Bush_Common_Flowers Grass_Common_Short Fern_1
Mushroom_Common Pebble_Round_1 Pebble_Round_2 RockPath_Round_Small_1""".split()

HEXAGON = """tiles/base/hex_grass tiles/base/hex_water tiles/coast/hex_coast_A tiles/coast/hex_coast_B
tiles/coast/hex_coast_C buildings/red/building_tavern_red buildings/red/building_home_A_red
buildings/red/building_home_B_red buildings/red/building_church_red buildings/red/building_well_red
buildings/red/building_tower_A_red buildings/red/building_watermill_red buildings/neutral/building_bridge_A
buildings/neutral/fence_wood_straight decoration/props/tent decoration/props/crate_A_small
decoration/props/crate_B_small decoration/props/barrel decoration/props/sack decoration/props/flag_red
decoration/props/bucket_water decoration/props/resource_lumber decoration/nature/trees_A_small
decoration/nature/trees_B_small decoration/nature/tree_single_A decoration/nature/rock_single_A
decoration/nature/rock_single_B decoration/nature/rock_single_C decoration/nature/hill_single_A
decoration/nature/waterplant_A decoration/nature/waterlily_A""".split()

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "kits")


def vendor(src_gltf: str, dst_dir: str, max_px: int = 0, normals: bool = False) -> None:
    with open(src_gltf) as f:
        j = json.load(f)
    src_dir = os.path.dirname(src_gltf)
    for m in j.get("materials", []):
        for k in ("occlusionTexture", "emissiveTexture") + (() if normals else ("normalTexture",)):
            m.pop(k, None)
        pbr = m.get("pbrMetallicRoughness", {})
        pbr.pop("metallicRoughnessTexture", None)
    used = set()
    normal_imgs = set()
    for m in j.get("materials", []):
        t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if t is not None:
            used.add(t["index"])
        if m.get("normalTexture") is not None:
            used.add(m["normalTexture"]["index"])
            normal_imgs.add(j["textures"][m["normalTexture"]["index"]]["source"])
    # Board-sized pieces (nature) are shrunk to 512 px; they cover a few dozen pixels on screen.
    # Renumber the textures and images that are still used.
    tex_map, img_map, textures, images = {}, {}, [], []
    for i in sorted(used):
        t = dict(j["textures"][i])
        src = t["source"]
        if src not in img_map:
            img_map[src] = len(images)
            images.append(j["images"][src])
        t["source"] = img_map[src]
        tex_map[i] = len(textures)
        textures.append(t)
    for m in j.get("materials", []):
        t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if t is not None:
            t["index"] = tex_map[t["index"]]
        if m.get("normalTexture") is not None:
            m["normalTexture"]["index"] = tex_map[m["normalTexture"]["index"]]
    normal_uris = {j["images"][i]["uri"] for i in normal_imgs}
    if textures:
        j["textures"], j["images"] = textures, images
    else:
        j.pop("textures", None)
        j.pop("images", None)
        j.pop("samplers", None)
    os.makedirs(dst_dir, exist_ok=True)
    for b in j.get("buffers", []):
        shutil.copy(os.path.join(src_dir, b["uri"]), os.path.join(dst_dir, b["uri"]))
    for im in images:
        dst = os.path.join(dst_dir, im["uri"])
        if not os.path.exists(dst):
            shutil.copy(os.path.join(src_dir, im["uri"]), dst)
            if max_px:
                shrink(dst, max_px)
            elif im["uri"] in normal_uris:
                shrink(dst, 1024)   # carved detail only; half size is plenty
    with open(os.path.join(dst_dir, os.path.basename(src_gltf)), "w") as f:
        json.dump(j, f, separators=(",", ":"))


def shrink(path: str, max_px: int) -> None:
    """Halve a texture until it fits in max_px (needs Pillow)."""
    from PIL import Image
    im = Image.open(path)
    if max(im.size) > max_px:
        f = max_px / max(im.size)
        im.resize((round(im.size[0] * f), round(im.size[1] * f)), Image.LANCZOS).save(path, optimize=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--props")
    ap.add_argument("--nature")
    ap.add_argument("--hexagon")
    a = ap.parse_args()
    if a.props:
        for n in PROPS:
            vendor(os.path.join(a.props, "Exports", "glTF", n + ".gltf"), os.path.join(ROOT, "fantasy_props"), normals=True)
        shutil.copy(os.path.join(a.props, "License_Standard.txt"), os.path.join(ROOT, "fantasy_props", "License.txt"))
    if a.nature:
        for n in NATURE:
            vendor(os.path.join(a.nature, "glTF", n + ".gltf"), os.path.join(ROOT, "nature"), 512)
        shutil.copy(os.path.join(a.nature, "License_Standard.txt"), os.path.join(ROOT, "nature", "License.txt"))
    if a.hexagon:
        base = os.path.join(a.hexagon, "addons", "kaykit_medieval_hexagon_pack")
        for n in HEXAGON:
            vendor(os.path.join(base, "Assets", "gltf", n + ".gltf"), os.path.join(ROOT, "hexagon"))
        shutil.copy(os.path.join(a.hexagon, "LICENSE.txt"), os.path.join(ROOT, "hexagon", "License.txt"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
