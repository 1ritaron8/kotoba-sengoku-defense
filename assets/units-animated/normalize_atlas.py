"""Pack imagegen's existing 24 cutouts into exact runtime cells, without redrawing poses."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent
SOURCES = {
    "archer": "exec-b1ac6dfe-6c4d-41f4-acbd-2f7587b1c075.png",
    "spear": "exec-d00b7946-a153-4612-9f08-c6c82fb92e15.png",
    "samurai": "exec-545204df-20d6-4e6c-b1e4-cb055c6d4af6.png",
    "commander": "exec-7ca60e99-6b1c-4a02-be61-b90acb87b26c.png",
    "enemy_light": "exec-1a440420-0b13-4c8b-a4cd-63974bb04d3b.png",
    "enemy_heavy": "exec-f6bda7ef-b54a-45a8-9560-9c197c598241.png",
}


def connected_cutouts(alpha):
    mask = alpha > 32
    height, width = mask.shape
    labels = np.zeros(mask.shape, dtype=np.int32)
    found = []
    label = 0
    for y in range(height):
        for x_raw in np.flatnonzero(mask[y]):
            x = int(x_raw)
            if not mask[y, x]:
                continue
            label += 1
            stack = [(x, y)]
            mask[y, x] = False
            area = 0
            left = right = x
            top = bottom = y
            while stack:
                px, py = stack.pop()
                labels[py, px] = label
                area += 1
                left, right = min(left, px), max(right, px)
                top, bottom = min(top, py), max(bottom, py)
                for nx, ny in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]:
                    if 0 <= nx < width and 0 <= ny < height and mask[ny, nx]:
                        mask[ny, nx] = False
                        stack.append((nx, ny))
            if area > 1000:
                found.append({"label": label, "area": area, "box": [left, top, right + 1, bottom + 1]})
    assert len(found) == 24, f"Expected 24 complete poses, found {len(found)}"
    by_cell = {}
    for component in found:
        left, top, right, bottom = component["box"]
        key = ((top + bottom) // 512, (left + right) // 512)
        assert key not in by_cell, f"Two bodies share cell {key}"
        by_cell[key] = component
    assert set(by_cell) == {(r, c) for r in range(4) for c in range(6)}
    return labels, by_cell


def pack(name, source):
    image = Image.open(source).convert("RGBA")
    assert image.size == (1536, 1024)
    pixels = np.array(image)
    labels, cutouts = connected_cutouts(pixels[:, :, 3])
    extracted = {}
    for key, component in cutouts.items():
        left, top, right, bottom = component["box"]
        left, top = max(0, left - 4), max(0, top - 4)
        right, bottom = min(image.width, right + 4), min(image.height, bottom + 4)
        sprite = image.crop((left, top, right, bottom))
        connected = Image.fromarray((labels[top:bottom, left:right] == component["label"]).astype(np.uint8) * 255)
        # Preserve imagegen's antialiased alpha around the already generated cutout.
        edge = np.array(connected.filter(ImageFilter.MaxFilter(9))) > 0
        rgba = np.array(sprite)
        rgba[:, :, 3] = np.where(edge, rgba[:, :, 3], 0)
        sprite = Image.fromarray(rgba)
        box = sprite.getbbox()
        assert box
        extracted[key] = sprite.crop(box)
    max_width = max(sprite.width for sprite in extracted.values())
    max_height = max(sprite.height for sprite in extracted.values())
    scale = min(1.0, 216 / max_width, 216 / max_height)
    atlas = Image.new("RGBA", (1536, 1024), (0, 0, 0, 0))
    frame_report = []
    for row in range(4):
        for column in range(6):
            sprite = extracted[(row, column)]
            sprite = sprite.resize((round(sprite.width * scale), round(sprite.height * scale)), Image.Resampling.LANCZOS)
            alpha = np.array(sprite.getchannel("A"), dtype=np.float64)
            mass = alpha.sum(axis=0)
            body_x = int(np.searchsorted(np.cumsum(mass), mass.sum() / 2))
            x = max(20, min(236 - sprite.width, 128 - body_x))
            y = 228 - sprite.height
            atlas.alpha_composite(sprite, (column * 256 + x, row * 256 + y))
            frame = atlas.crop((column * 256, row * 256, (column + 1) * 256, (row + 1) * 256))
            frame_report.append({"row": row, "frame": column, "bounds": list(frame.getbbox()), "sha256": hashlib.sha256(frame.tobytes()).hexdigest()})
    destination = ROOT / (name + ".png")
    atlas.save(destination)
    assert len({frame["sha256"] for frame in frame_report}) == 24
    assert all(0 < f["bounds"][0] < f["bounds"][2] < 256 and 0 < f["bounds"][1] < f["bounds"][3] < 256 for f in frame_report)
    return {"id": name, "size": list(atlas.size), "mode": atlas.mode, "columns": 6, "rows": 4, "cellWidth": 256, "cellHeight": 256, "baseline": 228, "uniformScale": scale, "transparentPixels": int(np.sum(np.array(atlas.getchannel("A")) == 0)), "frameCount": 24, "distinctFrames": 24, "frames": frame_report, "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("source_directory", type=Path)
    args = parser.parse_args()
    reports = []
    for name, filename in SOURCES.items():
        reports.append(pack(name, args.source_directory / filename))
        print(name, "24 distinct complete poses, transparent RGBA, 256 cells, baseline 228")
    (ROOT / "validation.json").write_text(json.dumps({"sprites": reports}, ensure_ascii=False, indent=2), encoding="utf-8")
