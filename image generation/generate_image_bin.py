#!/usr/bin/env python3
"""Generate IMAGE.BIN with simple RGB332 patterns.

Default output size is 320x240 (76800 bytes), RGB332 format.
python generate_image_bin.py -o IMAGE.BIN -p gradient
python generate_image_bin.py -o IMAGE.BIN -p checker -b 8
python generate_image_bin.py -o IMAGE.BIN -p stripes -b 16
python generate_image_bin.py -o IMAGE.BIN -p ramp
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def clamp_u8(value: int) -> int:
    return max(0, min(255, value))


def rgb888_to_rgb332(r: int, g: int, b: int) -> int:
    r3 = (clamp_u8(r) >> 5) & 0x07
    g3 = (clamp_u8(g) >> 5) & 0x07
    b2 = (clamp_u8(b) >> 6) & 0x03
    return (r3 << 5) | (g3 << 2) | b2


def pattern_gradient(x: int, y: int, width: int, height: int) -> int:
    # Smooth gradient across X and Y
    r = (x * 255) // max(1, width - 1)
    g = (y * 255) // max(1, height - 1)
    b = ((x + y) * 255) // max(1, width + height - 2)
    return rgb888_to_rgb332(r, g, b)


def pattern_checker(x: int, y: int, block: int) -> int:
    # Checkerboard in two colors
    on = ((x // block) + (y // block)) % 2 == 0
    return rgb888_to_rgb332(255, 255, 255) if on else rgb888_to_rgb332(0, 0, 0)


def pattern_stripes(x: int, y: int, block: int) -> int:
    # Vertical color stripes
    stripe = (x // block) % 6
    colors = [
        (255, 0, 0),
        (0, 255, 0),
        (0, 0, 255),
        (255, 255, 0),
        (0, 255, 255),
        (255, 0, 255),
    ]
    r, g, b = colors[stripe]
    return rgb888_to_rgb332(r, g, b)


def pattern_ramp(x: int, y: int, width: int, height: int) -> int:
    # Color ramp to stress RGB332 mapping
    r = (x * 255) // max(1, width - 1)
    g = ((width - 1 - x) * 255) // max(1, width - 1)
    b = (y * 255) // max(1, height - 1)
    return rgb888_to_rgb332(r, g, b)


def generate(width: int, height: int, pattern: str, block: int) -> bytes:
    data = bytearray(width * height)
    for y in range(height):
        for x in range(width):
            if pattern == "gradient":
                val = pattern_gradient(x, y, width, height)
            elif pattern == "checker":
                val = pattern_checker(x, y, block)
            elif pattern == "stripes":
                val = pattern_stripes(x, y, block)
            elif pattern == "ramp":
                val = pattern_ramp(x, y, width, height)
            else:
                raise ValueError(f"Unknown pattern: {pattern}")
            data[y * width + x] = val
    return bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate IMAGE.BIN (RGB332)")
    parser.add_argument("-o", "--output", default="IMAGE.BIN", help="Output file path")
    parser.add_argument("-W", "--width", type=int, default=320, help="Image width")
    parser.add_argument("-H", "--height", type=int, default=240, help="Image height")
    parser.add_argument(
        "-p",
        "--pattern",
        choices=["gradient", "checker", "stripes", "ramp"],
        default="gradient",
        help="Pattern type",
    )
    parser.add_argument("-b", "--block", type=int, default=16, help="Block size for checker/stripes")
    args = parser.parse_args()

    data = generate(args.width, args.height, args.pattern, args.block)
    out_path = Path(args.output)
    out_path.write_bytes(data)
    print(f"Wrote {len(data)} bytes to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
