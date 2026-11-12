"""生成 dsh-mobile 的主屏幕图标（iOS 180px、通用 192/512）。

用法：python tools/make-icons.py
输出：assets/icon-180.png assets/icon-192.png assets/icon-512.png
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / "assets"
SIZES = (180, 192, 512)

TOP = (75, 107, 255)
BOTTOM = (138, 75, 255)
INK = (255, 255, 255)


def find_font(size: int) -> ImageFont.FreeTypeFont:
    for name in ("seguisb.ttf", "segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default(size)


def gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size), TOP)
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(1, size - 1)
        draw.line(
            [(0, y), (size, y)],
            fill=(
                round(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
                round(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
                round(TOP[2] + (BOTTOM[2] - TOP[2]) * t),
            ),
        )
    return img


def glyph(img: Image.Image) -> Image.Image:
    size = img.size[0]
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    # 三道"进度条"，对应 DSH 的会话进度感
    bar_w = size * 0.10
    gap = size * 0.085
    total = bar_w * 3 + gap * 2
    x = (size - total) / 2
    heights = (0.30, 0.50, 0.40)
    base_y = size * 0.60
    for h in heights:
        top = base_y - size * h
        draw.rounded_rectangle(
            [x, top, x + bar_w, base_y],
            radius=bar_w / 2,
            fill=INK + (235,),
        )
        x += bar_w + gap

    # 底部一条横线，压住视觉重心
    draw.rounded_rectangle(
        [size * 0.30, size * 0.68, size * 0.70, size * 0.68 + size * 0.035],
        radius=size * 0.018,
        fill=INK + (170,),
    )
    return Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for size in SIZES:
        icon = glyph(gradient(size))
        icon.save(OUT / f"icon-{size}.png", "PNG", optimize=True)
        print(f"wrote {OUT / f'icon-{size}.png'} ({icon.size[0]}x{icon.size[1]})")


if __name__ == "__main__":
    main()
