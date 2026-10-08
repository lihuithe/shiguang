"""生成 App 圖示：暖色漸層背景上三張扇形疊放的照片卡片，呼應首頁「輕觸開始回顧」。

用法：python scripts/make_icon.py
輸出：App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png（1024×1024，無透明通道）
"""
import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # 先以 4 倍尺寸繪製再縮小，邊緣更平滑
S = SIZE * SCALE

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "App", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def vertical_gradient(w, h, top, bottom):
    column = Image.new("RGB", (1, h))
    for y in range(h):
        column.putpixel((0, y), lerp(top, bottom, y / max(h - 1, 1)))
    return column.resize((w, h))


def background():
    img = vertical_gradient(S, S, (92, 52, 30), (22, 13, 10))
    # 中央偏上的暖光
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse((S * 0.12, S * 0.10, S * 0.88, S * 0.86), fill=150)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.14))
    warm = Image.new("RGB", (S, S), (214, 120, 60))
    return Image.composite(warm, img, glow)


def rounded_mask(w, h, r):
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)
    return mask


def scene_sunset(w, h):
    img = vertical_gradient(w, h, (255, 132, 78), (255, 206, 120))
    d = ImageDraw.Draw(img)
    r = w * 0.17
    cx, cy = w * 0.5, h * 0.52
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 243, 214))
    d.polygon([(0, h * 0.62), (w * 0.30, h * 0.46), (w * 0.55, h * 0.64), (w, h * 0.50), (w, h), (0, h)], fill=(122, 66, 96))
    d.polygon([(0, h * 0.74), (w * 0.42, h * 0.60), (w * 0.78, h * 0.76), (w, h * 0.70), (w, h), (0, h)], fill=(74, 40, 72))
    return img


def scene_forest(w, h):
    img = vertical_gradient(w, h, (170, 218, 182), (70, 134, 98))
    d = ImageDraw.Draw(img)
    d.rectangle((0, h * 0.80, w, h), fill=(40, 86, 60))
    # 三棵松樹，每棵由三層三角形疊成
    for x, base, height in [(0.24, 0.84, 0.46), (0.56, 0.86, 0.58), (0.84, 0.84, 0.40)]:
        for layer in range(3):
            top = h * (base - height + layer * height * 0.22)
            half = w * (0.10 + layer * 0.035)
            bottom = h * (base - height * (0.45 - layer * 0.2))
            d.polygon([(w * x, top), (w * x - half, bottom), (w * x + half, bottom)], fill=(28, 84, 58))
        d.rectangle((w * x - w * 0.015, h * (base - 0.06), w * x + w * 0.015, h * base), fill=(70, 46, 32))
    return img


def scene_sea(w, h):
    img = vertical_gradient(w, h, (246, 112, 96), (196, 52, 72))
    d = ImageDraw.Draw(img)
    r = w * 0.20
    cx, cy = w * 0.5, h * 0.50
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 204, 110))
    d.rectangle((0, h * 0.56, w, h), fill=(120, 34, 66))
    for i, y in enumerate([0.62, 0.70, 0.79]):
        inset = w * (0.22 - i * 0.06)
        d.rounded_rectangle((inset, h * y, w - inset, h * y + h * 0.025), radius=h * 0.0125, fill=(255, 190, 120))
    return img


def card(scene, w, h):
    border = int(w * 0.045)
    radius = int(w * 0.10)
    outer = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    inner_w, inner_h = w - border * 2, h - border * 2
    inner = scene(inner_w, inner_h).convert("RGBA")
    inner.putalpha(rounded_mask(inner_w, inner_h, max(radius - border, 1)))
    outer.alpha_composite(inner, (border, border))
    outer.putalpha(rounded_mask(w, h, radius))
    return outer


def place(canvas, layer, center, angle):
    rotated = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - rotated.width / 2)
    y = int(center[1] - rotated.height / 2)

    # 柔和投影：四周留白再模糊，避免被圖層邊界切出硬邊
    pad = int(S * 0.06)
    alpha = Image.new("L", (rotated.width + pad * 2, rotated.height + pad * 2), 0)
    alpha.paste(rotated.getchannel("A").point(lambda a: int(a * 0.5)), (pad, pad))
    alpha = alpha.filter(ImageFilter.GaussianBlur(S * 0.02))
    shadow = Image.new("RGBA", alpha.size, (0, 0, 0, 255))
    shadow.putalpha(alpha)
    canvas.alpha_composite(shadow, (x - pad, y - pad + int(S * 0.02)))
    canvas.alpha_composite(rotated, (x, y))


def main():
    canvas = background().convert("RGBA")

    back_w, back_h = int(S * 0.36), int(S * 0.47)
    front_w, front_h = int(S * 0.42), int(S * 0.55)

    place(canvas, card(scene_forest, back_w, back_h), (S * 0.31, S * 0.47), 13)
    place(canvas, card(scene_sea, back_w, back_h), (S * 0.69, S * 0.47), -11)
    place(canvas, card(scene_sunset, front_w, front_h), (S * 0.50, S * 0.53), 0)

    icon = canvas.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    icon.save(OUTPUT, "PNG", optimize=True)
    print(f"saved {OUTPUT}")


if __name__ == "__main__":
    main()
