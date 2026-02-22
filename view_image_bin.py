#!/usr/bin/env python3
"""Preview RGB332 IMAGE.BIN by showing it directly in a window.

Default size is 320x240. Optional PPM output is supported.

python view_image_bin.py IMAGE.BIN
python view_image_bin.py IMAGE.BIN --ascii
python view_image_bin.py IMAGE.BIN -o preview.ppm
"""

from __future__ import annotations

import argparse
import base64
from pathlib import Path
import tempfile
import tkinter as tk


def rgb332_to_rgb888(val: int) -> tuple[int, int, int]:
    r3 = (val >> 5) & 0x07
    g3 = (val >> 2) & 0x07
    b2 = val & 0x03
    r = (r3 << 5) | (r3 << 2) | (r3 >> 1)
    g = (g3 << 5) | (g3 << 2) | (g3 >> 1)
    b = (b2 << 6) | (b2 << 4) | (b2 << 2) | b2
    return r, g, b


def to_ppm_bytes(data: bytes, width: int, height: int) -> bytes:
    if len(data) != width * height:
        raise ValueError(f"Expected {width*height} bytes, got {len(data)}")
    header = f"P6\n{width} {height}\n255\n".encode("ascii")
    rgb_bytes = bytearray(width * height * 3)
    for i, val in enumerate(data):
        r, g, b = rgb332_to_rgb888(val)
        base = i * 3
        rgb_bytes[base] = r
        rgb_bytes[base + 1] = g
        rgb_bytes[base + 2] = b
    return header + rgb_bytes


def write_ppm(data: bytes, width: int, height: int, out_path: Path) -> None:
    out_path.write_bytes(to_ppm_bytes(data, width, height))


def show_image(ppm_bytes: bytes, title: str) -> None:
    # Tk on Windows can be picky about in-memory PPM; use a temp file.
    with tempfile.NamedTemporaryFile(delete=False, suffix=".ppm") as tmp:
        tmp.write(ppm_bytes)
        tmp_path = tmp.name

    root = tk.Tk()
    root.title(title)
    image = tk.PhotoImage(file=tmp_path)
    label = tk.Label(root, image=image)
    label.image = image
    label.pack()
    root.mainloop()


def ascii_preview(data: bytes, width: int, height: int, cols: int, rows: int) -> str:
    # Downsample into a small grid and map luminance to ASCII
    if len(data) != width * height:
        raise ValueError(f"Expected {width*height} bytes, got {len(data)}")
    ramp = " .:-=+*#%@"
    step_x = max(1, width // cols)
    step_y = max(1, height // rows)
    lines = []
    for y in range(0, height, step_y):
        if len(lines) >= rows:
            break
        line = []
        for x in range(0, width, step_x):
            val = data[y * width + x]
            r, g, b = rgb332_to_rgb888(val)
            lum = (r * 30 + g * 59 + b * 11) // 100
            idx = (lum * (len(ramp) - 1)) // 255
            line.append(ramp[idx])
        lines.append("".join(line[:cols]))
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Preview RGB332 IMAGE.BIN")
    parser.add_argument("bin", help="Input IMAGE.BIN path")
    parser.add_argument("-W", "--width", type=int, default=320, help="Image width")
    parser.add_argument("-H", "--height", type=int, default=240, help="Image height")
    parser.add_argument("-o", "--output", default="", help="Optional PPM output path")
    parser.add_argument("--ascii", action="store_true", help="Print ASCII preview")
    parser.add_argument("--cols", type=int, default=80, help="ASCII columns")
    parser.add_argument("--rows", type=int, default=40, help="ASCII rows")
    args = parser.parse_args()

    data = Path(args.bin).read_bytes()
    ppm_bytes = to_ppm_bytes(data, args.width, args.height)
    show_image(ppm_bytes, title=f"{Path(args.bin).name} ({args.width}x{args.height})")

    if args.output:
        write_ppm(data, args.width, args.height, Path(args.output))
        print(f"Wrote {args.output}")

    if args.ascii:
        print(ascii_preview(data, args.width, args.height, args.cols, args.rows))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
