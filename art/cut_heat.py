# Turns the renders of render_heat.py (art/raw, 4x) into the 2x frames
# art/frames/delheat_01_<index>.png, writes art/tiles.json for
# tools/TilePack/build-tilepack.ps1, the item icons, a preview sheet and the
# poster.
#   python art/cut_heat.py
#
# One-cell sprites are a plain crop. A boiler or an intake is one render of
# the 3x3 cells around its anchor plus a mask of which cell every pixel
# stands on; the frame of a cell keeps only its own pixels (as in
# Delirium-Mines).
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
FRAMES = os.path.join(HERE, "frames")
TEXTURES = os.path.join(HERE, "..", "Contents", "mods", "DeliriumHeating", "42", "media", "textures")
TILESET = "delheat_01"
SCALE = 4
# The ground under an object is a shadow catcher: its shadow is black with
# some alpha. None of it goes into a frame: in the game a half-transparent
# shadow came out as a brown blot on the floor (a radiator on dark boards,
# 2026-11-16), and the game draws no shadows under vanilla furniture either.
SHADOW = 0.0

# Along an east-west pipe, along a north-south one.
PUMP = {"E": 16, "S": 42}
INLET = {"N": 17, "W": 38, "S": 39, "E": 40}
RISER = 41
SUPPORT = 43
TAP = {"N": 44, "W": 45, "S": 46, "E": 47}
# One level up is 192 px at 2x.
LEVEL = 192
RADIATOR = {"N": 18, "W": 19, "S": 20, "E": 21}
# render name: first index, cells wide, cells deep
STRUCTURES = {"boiler_S": (22, 3, 2), "boiler_E": (28, 2, 3), "intake": (34, 2, 2)}
SOLID = {"solidtrans": "", "BlocksPlacement": ""}


def load(name):
    return np.asarray(Image.open(os.path.join(RAW, name)).convert("RGBA"), dtype=np.float32) / 255.0


def is_shadow(img):
    # 0 on the object, 1 on bare ground in its shadow.
    lum = img[..., :3].max(axis=2)
    return np.where(img[..., 3] < 0.98, 1 - np.clip(lum / 0.05, 0, 1), 0.0)


def soften_shadow(img, x0=None, x1=None):
    # x0..x1: the frame's columns in the 4x image. The shadow fades out
    # towards the frame's sides and bottom instead of being cut by them.
    strength = np.full(img.shape[:2], SHADOW, dtype=np.float32)
    if x0 is not None:
        h, w = img.shape[:2]
        xs = np.arange(w, dtype=np.float32)[None, :]
        ys = np.arange(h, dtype=np.float32)[:, None]
        strength = strength * np.clip((xs - x0) / 48, 0, 1) * np.clip((x1 - xs) / 48, 0, 1) * np.clip((h - ys) / 32, 0, 1)
    out = img.copy()
    out[..., 3] *= 1 - is_shadow(img) * (1 - strength)
    return out


def downsample(img):
    # Premultiplied box filter 4x -> 2x pixels.
    h, w = img.shape[0] // SCALE, img.shape[1] // SCALE
    pm = img.copy()
    pm[..., :3] *= pm[..., 3:4]
    return pm.reshape(h, SCALE, w, SCALE, 4).mean(axis=(1, 3))


def save(pm, index):
    a = pm[..., 3:4]
    rgb = np.where(a > 1e-6, pm[..., :3] / np.maximum(a, 1e-6), 0)
    out = (np.concatenate([rgb, a], axis=2) * 255 + 0.5).clip(0, 255).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(FRAMES, f"{TILESET}_{index}.png"))


def single(name, index):
    pm = downsample(soften_shadow(load(name + "_color.png"), 64 * SCALE, 192 * SCALE))
    save(pm[:, 64:192], index)


def window(dx, dy):
    return 128 + (dx - dy) * 64, (dx + dy) * 32


def structure(name):
    first, wide, deep = STRUCTURES[name]
    area = 384
    color = load(name + "_color.png")
    pm = downsample(soften_shadow(color))
    mask = load(name + "_mask.png")
    # The ground around the structure belongs to no cell: its shadow is dropped.
    mask[..., 3] = np.where(is_shadow(color) > 0.5, 0, mask[..., 3])
    col = np.clip(np.rint(mask[..., 0] * 2), 0, 2).astype(int)
    row = np.clip(np.rint(mask[..., 1] * 2), 0, 2).astype(int)
    ids = np.where(mask[..., 3] > 0.5, row * 3 + col, -1)
    votes = np.stack([(ids == k).reshape(area, SCALE, area, SCALE).sum(axis=(1, 3)) for k in range(9)])
    owner = np.where(votes.max(axis=0) > 0, votes.argmax(axis=0), -1)
    inside = np.zeros((area, area), bool)
    for dy in range(deep):
        for dx in range(wide):
            x0, y0 = window(dx, dy)
            win = pm[y0:y0 + 256, x0:x0 + 128].copy()
            mine = owner[y0:y0 + 256, x0:x0 + 128] == dy * 3 + dx
            win[~mine] = 0
            inside[y0:y0 + 256, x0:x0 + 128] |= mine
            save(win, first + dy * wide + dx)
    # Mostly silhouette fringe whose mask sample hit the ground behind.
    print(name, "pixels outside their cell's frame:", int(((owner >= 0) & ~inside).sum()))


def frame(index):
    return Image.open(os.path.join(FRAMES, f"{TILESET}_{index}.png"))


def assemble(name):
    first, wide, deep = STRUCTURES[name]
    img = Image.new("RGBA", (384, 384), (0, 0, 0, 0))
    for dy in range(deep):
        for dx in range(wide):
            img.alpha_composite(frame(first + dy * wide + dx), window(dx, dy))
    return img


def scene():
    # A little network drawn the way the game would: levels bottom up, cells
    # back to front. The main ends in heat units at the four walls; the
    # radiators stand apart from the pipes; one branch crosses in the air.
    cells = {}

    def put(x, y, z, *indices):
        cells.setdefault((x, y, z), []).extend(indices)

    nodes = {(x, 3, 0) for x in range(0, 7)} | {(3, y, 0) for y in range(0, 7)} | {(6, y, 0) for y in range(3, 6)}
    nodes |= {(0, 4, 0), (0, 5, 0), (0, 9, 0), (0, 10, 0), (6, 2, 0)} | {(0, y, 1) for y in range(5, 10)}
    devices = {(6, 5, 0): INLET["E"], (4, 3, 0): PUMP["E"], (3, 5, 0): PUMP["S"], (3, 0, 0): INLET["N"], (3, 6, 0): INLET["S"], (0, 10, 0): INLET["W"], (6, 2, 0): TAP["N"]}
    for (x, y, z) in nodes:
        mask = sum(bit for bit, (dx, dy) in ((1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0)))
                   if (x + dx, y + dy, z) in nodes)
        # A pump carries its own length of pipe.
        if devices.get((x, y, z)) not in PUMP.values():
            put(x, y, z, mask)
        if (x, y, z + 1) in nodes:
            put(x, y, z, RISER)
        if (x, y, z) in devices:
            put(x, y, z, devices[(x, y, z)])
    put(0, 7, 0, SUPPORT)
    put(5, 7, 0, RADIATOR["N"])
    put(8, 6, 0, RADIATOR["E"])
    put(4, 5, 0, RADIATOR["W"])
    put(7, 8, 0, RADIATOR["S"])
    w, h = 12 * 128 + 64, 11 * 64 + 256
    img = Image.new("RGBA", (w, h), (74, 96, 58, 255))
    for (x, y, z) in sorted(cells, key=lambda c: (c[2], c[0] + c[1], c[0])):
        for index in cells[(x, y, z)]:
            img.alpha_composite(frame(index), (w // 2 - 64 + (x - y) * 64, 32 + (x + y) * 32 - z * LEVEL + 100))
    return img


def icon(img, name):
    # Item icon: the object without its shadow, squared, 32x32.
    arr = np.asarray(img.convert("RGBA")).copy()
    ys, xs = np.nonzero(arr[..., 3] > 150)
    arr[..., 3] = np.where(arr[..., 3] > 110, arr[..., 3], 0)
    crop = Image.fromarray(arr, "RGBA").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    side = max(crop.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
    os.makedirs(TEXTURES, exist_ok=True)
    square.resize((32, 32), Image.LANCZOS).save(os.path.join(TEXTURES, f"Item_DelHeat{name}.png"))


def tiles_json():
    tiles = []

    def add(index, props=None):
        tiles.append({"index": index, "png": f"frames/{TILESET}_{index}.png", "props": props or {}})

    for mask in range(16):
        add(mask)
    for index in PUMP.values():
        add(index, SOLID)
    add(RISER)
    add(SUPPORT)
    for index in list(RADIATOR.values()) + list(INLET.values()) + list(TAP.values()):
        add(index)
    for first, wide, deep in STRUCTURES.values():
        for cell in range(wide * deep):
            add(first + cell, SOLID)
    spec = {"pack": "delheat", "tileset": TILESET, "columns": 8, "rows": 8, "tiles": tiles}
    with open(os.path.join(HERE, "tiles.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(spec, indent=2) + "\n")


def main():
    os.makedirs(FRAMES, exist_ok=True)
    for mask in range(16):
        single(f"pipe_{mask}", mask)
    single("pump", PUMP["E"])
    single("pump_S", PUMP["S"])
    single("riser", RISER)
    single("support", SUPPORT)
    for facing, index in RADIATOR.items():
        single("radiator_" + facing, index)
    for facing, index in INLET.items():
        single("inlet_" + facing, index)
    for facing, index in TAP.items():
        single("tap_" + facing, index)
    for name in STRUCTURES:
        structure(name)
    tiles_json()

    icon(frame(10), "Pipe")
    icon(frame(RADIATOR["N"]), "Radiator")
    icon(frame(SUPPORT), "Support")
    icon(frame(INLET["N"]), "Inlet")
    icon(frame(TAP["N"]), "WaterUnit")
    icon(frame(PUMP["E"]), "Pump")
    icon(assemble("intake"), "Intake")
    icon(assemble("boiler_S"), "Boiler")

    net = scene()
    sheet = Image.new("RGBA", (net.width + 3 * 384, max(net.height, 384)), (74, 96, 58, 255))
    sheet.alpha_composite(net)
    for i, name in enumerate(STRUCTURES):
        sheet.alpha_composite(assemble(name), (net.width + i * 384, 0))
    sheet.save(os.path.join(HERE, "preview_sheet.png"))

    poster = Image.new("RGBA", (384, 384), (52, 66, 46, 255))
    poster.alpha_composite(assemble("boiler_S"), (0, 40))
    poster.resize((256, 256), Image.LANCZOS).convert("RGB").save(os.path.join(HERE, "poster.png"))
    print("frames:", len(os.listdir(FRAMES)))


if __name__ == "__main__":
    main()
