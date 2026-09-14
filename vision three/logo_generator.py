from PIL import Image, ImageDraw, ImageFilter
import math
import random
import numpy as np

FINAL_SIZE = 512
SS = 4                       # supersampling factor for crisp, high-quality edges
SIZE = FINAL_SIZE * SS

img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
draw = ImageDraw.Draw(img)

center = (SIZE // 2, SIZE // 2)

random.seed(3)
# "Vision 3": bigger dots than Vision 1/2 (0.045 -> 0.065), and the Vision 2
# grid background removed entirely (§ user feedback: "remove the background
# cover which is the square lines boxes") -- back to a plain white ground,
# same dot cluster and lighting, just larger, bolder dots.
dot_r = SIZE * 0.065

# Black dots in a rough / imperfect circle in the middle, not touching each other
ring_r_base = SIZE * 0.19   # widened a bit from Vision 1/2 (0.16) to give the bigger dots room
min_gap = dot_r * 2.3
n_dots = 6

placed = []
for i in range(n_dots):
    base_angle = (2 * math.pi / n_dots) * i
    for attempt in range(40):
        angle = base_angle + random.uniform(-0.3, 0.3)          # imperfect spacing
        ring_r = ring_r_base * random.uniform(0.85, 1.3)        # imperfect radius
        x = center[0] + ring_r * math.cos(angle)
        y = center[1] - ring_r * math.sin(angle)
        if all(math.hypot(x-px, y-py) >= min_gap for px, py in placed):
            placed.append((x, y))
            break
    else:
        placed.append((x, y))  # fallback if it never found a clear spot

def blob_points(cx, cy, r, seed, n=64, irregularity=0.10):
    """A soft, slightly irregular blob outline instead of a perfectly accurate circle."""
    rnd = random.Random(seed)
    harmonics = [(rnd.choice([2, 3, 4, 5]), rnd.uniform(0, 2 * math.pi), rnd.uniform(0.5, 1.0))
                 for _ in range(3)]
    pts = []
    for i in range(n):
        theta = 2 * math.pi * i / n
        rad = r
        for freq, phase, amp in harmonics:
            rad += r * irregularity * amp / len(harmonics) * math.sin(freq * theta + phase)
        pts.append((cx + rad * math.cos(theta), cy - rad * math.sin(theta)))
    return pts


def draw_blob(draw_obj, cx, cy, r, seed, fill):
    draw_obj.polygon(blob_points(cx, cy, r, seed), fill=fill)


blue_pos = (SIZE * 0.315, SIZE * 0.30)

# One of the randomly-placed black dots ends up tucked right under/behind the
# blue dot, reading as a stray dark smudge peeking out from under it (§ user
# feedback: "remove the black dot under the blue dot") -- drop whichever
# placed dot sits closest to the blue dot before drawing anything, keeping
# every *other* dot's position and blob-seed exactly as before (seeds stay
# tied to each dot's original index, not its position in the shortened list,
# so the remaining five don't subtly change shape).
closest_idx = min(range(len(placed)), key=lambda i: math.hypot(placed[i][0]-blue_pos[0], placed[i][1]-blue_pos[1]))
placed_with_seed = [(x, y, 100 + i) for i, (x, y) in enumerate(placed) if i != closest_idx]
placed = [(x, y) for (x, y, _) in placed_with_seed]

all_dots = placed + [blue_pos]

# NOTE: Vision 2's grid-of-lines background is intentionally not drawn here —
# plain white background per this version's request.

for (x, y, seed) in placed_with_seed:
    draw_blob(draw, x, y, dot_r, seed=seed, fill=(20, 20, 20, 255))

# Blue dot: its own separate dot, same size, off to the top-left, not touching/containing the black dots
draw_blob(draw, blue_pos[0], blue_pos[1], dot_r, seed=999, fill=(41, 121, 255, 255))


def make_radial_patch(radius_px, rgb, max_alpha):
    """Smooth soft-edged radial gradient patch (RGBA), full opacity at center fading to 0."""
    radius_px = max(2, int(round(radius_px)))
    d = radius_px * 2
    yy, xx = np.mgrid[0:d, 0:d]
    dist = np.sqrt((xx - radius_px) ** 2 + (yy - radius_px) ** 2) / radius_px
    dist = np.clip(dist, 0, 1)
    # smoothstep-style falloff for a soft, natural glow
    falloff = np.clip(1 - dist, 0, 1) ** 1.8
    alpha = (falloff * max_alpha).astype(np.uint8)
    patch = np.zeros((d, d, 4), dtype=np.uint8)
    patch[..., 0] = rgb[0]
    patch[..., 1] = rgb[1]
    patch[..., 2] = rgb[2]
    patch[..., 3] = alpha
    return Image.fromarray(patch, "RGBA")


# Light comes from the top-right: highlight toward top-right, soft shadow toward bottom-left
light_dir = (0.7, -0.7)  # normalized-ish (x right, y up)

highlight_r = dot_r * 0.5
shadow_r = dot_r * 0.65
offset = dot_r * 0.4
shadow_offset = dot_r * 0.6   # pushed further out so the shadow peeks past the dot's edge

highlight_patch = make_radial_patch(highlight_r, (255, 255, 255), 235)
shadow_patch = make_radial_patch(shadow_r, (0, 0, 0), 130)

shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
highlight_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

for (cx, cy) in all_dots:
    # shadow: opposite side of the light (bottom-left), mirrors the highlight so it peeks past the edge
    sx = cx - shadow_offset
    sy = cy + shadow_offset
    shadow_layer.alpha_composite(shadow_patch, (int(sx - shadow_r), int(sy - shadow_r)))

    # highlight: top-right, where the sun hits
    hx = cx + offset
    hy = cy - offset
    highlight_layer.alpha_composite(highlight_patch, (int(hx - highlight_r), int(hy - highlight_r)))

shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=SIZE * 0.006))
highlight_layer = highlight_layer.filter(ImageFilter.GaussianBlur(radius=SIZE * 0.004))

# shadows sit under the dots' glow, highlights sit above
img = Image.alpha_composite(img, shadow_layer)

# redraw dots on top of shadow layer so shadow only peeks out from behind each dot
draw = ImageDraw.Draw(img)
for (x, y, seed) in placed_with_seed:
    draw_blob(draw, x, y, dot_r, seed=seed, fill=(20, 20, 20, 255))
draw_blob(draw, blue_pos[0], blue_pos[1], dot_r, seed=999, fill=(41, 121, 255, 255))

img = Image.alpha_composite(img, highlight_layer)

# Downsample from supersampled render for smooth, high-quality anti-aliased edges
img = img.resize((FINAL_SIZE, FINAL_SIZE), Image.LANCZOS)

img.save("logo.png")

# Also a smaller favicon-style version
small = img.resize((64, 64), Image.LANCZOS)
small.save("favicon.png")

# A flattened, fully-opaque 1024x1024 version for the app icon (iOS icons
# can't carry an alpha channel).
icon = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
icon.save("icon_1024.png")

print("done")
