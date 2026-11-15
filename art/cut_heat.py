# Turns the renders of render_heat.py (art/raw, 4x) into the 2x frames
# art/frames/delheat_01_<index>.png, writes art/tiles.json for
# tools/TilePack/build-tilepack.ps1, a preview sheet and the poster.
#   python art/cut_heat.py
#
# One-cell sprites are a plain crop. A boiler is one render of the 3x3 cells
# around its anchor plus a mask of which cell every pixel stands on; the
# frame of a cell keeps only its own pixels (as in Delirium-Mines).
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
FRAMES = os.path.join(HERE, "frames")
TILESET = "delheat_01"
SCALE = 4
# The ground under an object is a shadow catcher: its shadow is black with
# some alpha. PZ sprites carry only a faint contact shadow.
SHADOW = 0.45

PUMP = 16
RADIATOR = {"N": 18, "W": 19, "S": 20, "E": 21}
BOILER = {"S": (22, 3, 2), "E": (28, 2, 3)}     # first index, cells wide, cells deep
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


def boiler(facing):
    first, wide, deep = BOILER[facing]
    area = 384
    color = load(f"boiler_{facing}_color.png")
    pm = downsample(soften_shadow(color))
    mask = load(f"boiler_{facing}_mask.png")
    # The ground around the boiler belongs to no cell: its shadow is dropped.
    mask[..., 3] = np.where(is_shadow(color) > 0.5, 0, mask[..., 3])
    col = np.clip(np.rint(mask[..., 0] * 2), 0, 2).astype(int)
    row = np.clip(np.rint(mask[..., 1] * 2), 0, 2).astype(int)
    ids = np.where(mask[..., 3] > 0.5, row * 3 + col, -1)
    votes = np.stack([(ids == k).reshape(area, SCALE, area, SCALE).sum(axis=(1, 3)) for k in range(9)])
    owner = np.where(votes.max(axis=0) > 0, votes.argmax(axis=0), -1)
    lost = 0
    for dy in range(deep):
        for dx in range(wide):
            x0, y0 = window(dx, dy)
            win = pm[y0:y0 + 256, x0:x0 + 128].copy()
            win[owner[y0:y0 + 256, x0:x0 + 128] != dy * 3 + dx] = 0
            save(win, first + dy * wide + dx)
    inside = np.zeros((area, area), bool)
    for dy in range(deep):
        for dx in range(wide):
            x0, y0 = window(dx, dy)
            inside[y0:y0 + 256, x0:x0 + 128] |= owner[y0:y0 + 256, x0:x0 + 128] == dy * 3 + dx
    lost = int(((owner >= 0) & ~inside).sum())
    print("boiler", facing, "solid pixels outside their cell's frame:", lost)


def frame(index):
    return Image.open(os.path.join(FRAMES, f"{TILESET}_{index}.png"))


def assemble_boiler(facing):
    first, wide, deep = BOILER[facing]
    img = Image.new("RGBA", (384, 384), (0, 0, 0, 0))
    for dy in range(deep):
        for dx in range(wide):
            img.alpha_composite(frame(first + dy * wide + dx), window(dx, dy))
    return img


def scene():
    # A little network drawn the way the game would: cells back to front.
    cells = {}

    def put(x, y, *indices):
        cells.setdefault((x, y), []).extend(indices)

    nodes = {(x, 3) for x in range(0, 7)} | {(3, y) for y in range(0, 7)} | {(6, y) for y in range(3, 6)}
    devices = {(3, 0): RADIATOR["N"], (6, 5): RADIATOR["E"], (0, 3): RADIATOR["W"], (3, 6): RADIATOR["S"], (5, 3): PUMP}
    for (x, y) in nodes:
        mask = sum(bit for bit, (dx, dy) in ((1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0)))
                   if (x + dx, y + dy) in nodes)
        put(x, y, mask)
        if (x, y) in devices:
            put(x, y, devices[(x, y)])
    w, h = 7 * 128 + 64, 7 * 64 + 256
    img = Image.new("RGBA", (w, h), (74, 96, 58, 255))
    for (x, y) in sorted(cells, key=lambda c: (c[0] + c[1], c[0])):
        for index in cells[(x, y)]:
            img.alpha_composite(frame(index), (w // 2 - 64 + (x - y) * 64, 64 + (x + y) * 32))
    return img


def tiles_json():
    tiles = []

    def add(index, props=None):
        tiles.append({"index": index, "png": f"frames/{TILESET}_{index}.png", "props": props or {}})

    for mask in range(16):
        add(mask)
    add(PUMP, SOLID)
    for index in RADIATOR.values():
        add(index)
    for first, wide, deep in BOILER.values():
        for cell in range(wide * deep):
            add(first + cell, SOLID)
    spec = {"pack": "delheat", "tileset": TILESET, "columns": 8, "rows": 8, "tiles": tiles}
    with open(os.path.join(HERE, "tiles.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(spec, indent=2) + "\n")


def main():
    os.makedirs(FRAMES, exist_ok=True)
    for mask in range(16):
        single(f"pipe_{mask}", mask)
    single("pump", PUMP)
    for facing, index in RADIATOR.items():
        single("radiator_" + facing, index)
    for facing in BOILER:
        boiler(facing)
    tiles_json()

    net = scene()
    sheet = Image.new("RGBA", (net.width + 2 * 384, max(net.height, 384)), (74, 96, 58, 255))
    sheet.alpha_composite(net)
    sheet.alpha_composite(assemble_boiler("S"), (net.width, 0))
    sheet.alpha_composite(assemble_boiler("E"), (net.width + 384, 0))
    sheet.save(os.path.join(HERE, "preview_sheet.png"))

    poster = Image.new("RGBA", (384, 384), (52, 66, 46, 255))
    poster.alpha_composite(assemble_boiler("S"), (0, 40))
    poster.resize((256, 256), Image.LANCZOS).convert("RGB").save(os.path.join(HERE, "poster.png"))
    print("frames:", len(os.listdir(FRAMES)))


if __name__ == "__main__":
    main()
