#!/usr/bin/env python3
"""
Draw the Peers sidebar/app icon.

The mark IS a HexAvatar — the same 5x5 left-right-symmetric identicon the app
draws for every identity, rendered from a fixed seed. Same xmur3 -> mulberry32
PRNG, same roll order, same ramp, same 22%-of-side rounded-square container on
the #0A0A0A ground, so the icon and the avatars are visibly one system.

Regenerate:  python3 scripts/make-sidebar-icon.py
"""
from PIL import Image, ImageDraw

SEED = "peers"
KIND_PREFIX = "c:"
RAMP = ["#B8420E", "#FF5000", "#FF7A33", "#FFB27A", "#FFE4D0"]
GROUND = "#0A0A0A"
N = 5
SIZE = 64
SUPERSAMPLE = 8  # draw large, downscale -> clean rounded corners without a shader

U32 = 0xFFFFFFFF


def imul(a: int, b: int) -> int:
    """JS Math.imul: 32-bit wrapping multiply, result as signed int32."""
    r = (a * b) & U32
    return r - 0x100000000 if r & 0x80000000 else r


def rng(seed: str):
    """xmur3 hash seeding a mulberry32 PRNG — a port of HexAvatar.tsx:43-59."""
    h = 1779033703 ^ len(seed)
    for ch in seed:
        h = imul(h ^ ord(ch), 3432918353)
        h = ((h << 13) & U32) | ((h & U32) >> 19)
        h = h - 0x100000000 if h & 0x80000000 else h
    a = imul(h ^ ((h & U32) >> 13), 3266489909)
    a = (a ^ ((a & U32) >> 16)) & U32

    state = {"a": a}

    def nxt() -> float:
        x = state["a"] & U32
        x = (x + 0x6D2B79F5) & U32
        state["a"] = x
        t = imul(x ^ ((x & U32) >> 15), 1 | x) & U32
        t = (t + (imul(t ^ ((t & U32) >> 7), 61 | t) & U32)) & U32
        t = (t ^ x) & U32
        return ((t ^ ((t & U32) >> 14)) & U32) / 4294967296.0

    return nxt


def cells(seed: str):
    """The filled cells, column-major, two rolls per cell but the colour roll
    consumed only when the cell is filled — the ordering is load-bearing."""
    r = rng(KIND_PREFIX + seed)
    out = []
    for x in range(3):
        for y in range(N):
            if r() > 0.5:
                continue
            fill = RAMP[int(r() * len(RAMP))]
            xs = [2] if x == 2 else [x, N - 1 - x]
            for xx in xs:
                out.append((xx, y, fill))
    return out


def main() -> None:
    s = SIZE * SUPERSAMPLE
    cell = s / N
    radius = int(s * 0.22)

    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=255)

    d.rectangle([0, 0, s, s], fill=GROUND)
    for x, y, fill in cells(SEED):
        d.rectangle([x * cell, y * cell, (x + 1) * cell, (y + 1) * cell], fill=fill)

    img.putalpha(mask)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)

    out = "qml/icons/Peers_sidebar.png"
    img.save(out)
    print(f"wrote {out} ({SIZE}x{SIZE}), {len(cells(SEED))} cells from seed '{SEED}'")


if __name__ == "__main__":
    main()
