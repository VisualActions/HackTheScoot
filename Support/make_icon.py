"""Draws the HackTheScoot app icon in code (no image generation).
Speedometer dial whose hub is a scooter-wheel axle. Run: python3 Support/make_icon.py"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

def hexc(h, a=255):
    h = h.lstrip("#"); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))

def draw(size=1024):
    S = size * 4  # supersample
    img = Image.new("RGBA", (S, S), hexc("#05070B"))
    # radial background
    bg = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(bg)
    for r in range(S // 2 * 14 // 10, 0, -S // 200):
        t = r / (S * 0.7)
        d.ellipse([S/2 - r, S/2 - r, S/2 + r, S/2 + r], fill=lerp(hexc("#1A2230"), hexc("#05070B"), min(1, t)))
    img = Image.alpha_composite(img, bg)
    d = ImageDraw.Draw(img)
    c = S / 2
    # wheel ring
    R0 = S * 0.37
    d.ellipse([c - R0, c - R0, c + R0, c + R0], outline=(255, 255, 255, 30), width=int(S * 0.035))
    # speed arc with glow
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0)); g = ImageDraw.Draw(glow)
    R1 = S * 0.31; w = int(S * 0.075)
    steps = 270
    for i in range(steps):
        t = i / steps
        col = lerp(hexc("#00E5FF"), hexc("#FF3B3B"), max(0, (t - 0.45) / 0.55))
        a0 = 135 + 270 * t; a1 = a0 + 270 / steps + 0.6
        for dd in (d, g):
            dd.arc([c - R1, c - R1, c + R1, c + R1], a0, a1, fill=col, width=w)
    # round caps
    for t in (0.0, 1.0):
        ang = math.radians(135 + 270 * t)
        col = hexc("#00E5FF") if t == 0 else hexc("#FF3B3B")
        x, y = c + R1 * math.cos(ang) - 0, c + R1 * math.sin(ang)
        rr = w / 2 - S * 0.0
        x -= (w / 2) * 0; 
        cx, cy = c + (R1 - w / 2) * math.cos(ang) + 0, c + (R1 - w / 2) * math.sin(ang)
        cx, cy = c + (R1 - w/2 + w/2) * math.cos(ang), c + (R1 - w/2 + w/2) * math.sin(ang)
        cx, cy = c + (R1 - w / 2) * math.cos(ang), c + (R1 - w / 2) * math.sin(ang)
        d.ellipse([cx - w/2, cy - w/2, cx + w/2, cy + w/2], fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.03))
    img = Image.alpha_composite(glow, img) if False else Image.alpha_composite(img, Image.blend(Image.new("RGBA", (S, S), (0,0,0,0)), glow, 0.55))
    d = ImageDraw.Draw(img)
    # ticks
    for i in range(10):
        ang = math.radians(-225 + i * 30)
        r_in, r_out = S * 0.205, S * 0.25
        d.line([c + r_in * math.cos(ang), c + r_in * math.sin(ang), c + r_out * math.cos(ang), c + r_out * math.sin(ang)],
               fill=(255, 255, 255, 140), width=int(S * 0.012))
    # needle (pointing to ~85%)
    ang = math.radians(-225 + 230)
    L = S * 0.25
    tip = (c + L * math.cos(ang), c + L * math.sin(ang))
    perp = ang + math.pi / 2; hw = S * 0.017
    base1 = (c + hw * math.cos(perp), c + hw * math.sin(perp)); base2 = (c - hw * math.cos(perp), c - hw * math.sin(perp))
    d.polygon([base1, tip, base2], fill=hexc("#FF3B3B"))
    # hub = wheel axle
    r = S * 0.045; d.ellipse([c - r, c - r, c + r, c + r], fill=(255, 255, 255, 255))
    r = S * 0.02; d.ellipse([c - r, c - r, c + r, c + r], fill=hexc("#05070B"))
    out = img.resize((size, size), Image.LANCZOS).convert("RGB")  # icons must be opaque
    return out

if __name__ == "__main__":
    dest = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "J078", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(dest, exist_ok=True)
    draw(1024).save(os.path.join(dest, "AppIcon-1024.png"))
    print("wrote", dest)
