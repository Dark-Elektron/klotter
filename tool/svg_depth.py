"""Lay the background symbol field onto a receding plane.

The wallpaper is a field of 223 maths symbols, each an SVG `<text>` element with
its own position, size, opacity and a random rotation.

Grading size alone was tried first and does not read. The reason is structural:
with the symbols at random angles on a flat field, a smaller symbol reads as a
smaller symbol, not a further one. Perspective needs *coherence* — everything
agreeing about where the vanishing point is — and size on its own supplies none.
(An earlier attempt scaled the nine `<g>` groups instead. Those are the
openclipart the artwork was built on; they sit behind the symbols and are not
what the eye reads.)

So each symbol is transformed as though it were lying on a ground plane tilted
away from the viewer. Three cues vary together with depth, which is what makes
it legible where any one alone was not:

  size          far symbols smaller
  foreshortening far symbols squashed vertically, as a tilted plane squashes
  shear         symbols lean toward the vanishing point, the more so when far

The random rotation is replaced rather than preserved: it is the thing that was
fighting the effect. A small deterministic jitter is kept so the field does not
look mechanically regular.

Every transform is anchored at the symbol's own `x`/`y`, so nothing moves — only
its shape changes. The composition you drew stays exactly where you put it.

Idempotent: the transform is a pure function of position, and the original size
and opacity are recorded on each element the first time it runs.

    python tool/svg_depth.py --check          # report, change nothing
    python tool/svg_depth.py                  # apply to every background
    python tool/svg_depth.py FILE [FILE ...]  # apply to some
"""

import argparse
import glob
import io
import math
import re

CANVAS = 1080.0

# The vanishing point, in canvas coordinates. Above the top edge, so the whole
# canvas is ground receding away from the viewer rather than a horizon sitting
# inside the picture. Slightly left of centre, to agree with the lighting.
VP_X, VP_Y = 470.0, -420.0

FAR_SCALE, NEAR_SCALE = 0.50, 1.55  # size at the far and near edges
FAR_SQUASH = 0.60  # vertical foreshortening at the far edge; 1.0 = none
SHEAR = 0.60  # lean toward the vanishing point, at the far edge
# Opacity multipliers. Kept close to 1: fading with distance is a real cue
# (aerial perspective) but these symbols start at around 0.6 opacity, so a
# fade that would be gentle on solid artwork takes them below the threshold of
# being seen at all. Depth here is carried by size, foreshortening and shear;
# opacity only nudges.
FAR_FADE, NEAR_FADE = 0.88, 1.12
JITTER = 0.055  # residual rotation, radians, so the field is not mechanical

TEXT = re.compile(r"<text[^>]*>")


def lerp(a, b, t):
    return a + (b - a) * t


def _num(tag, *patterns):
    for p in patterns:
        m = re.search(p, tag)
        if m:
            return float(m.group(1))
    return None


def perspective(x, y):
    """The matrix for a symbol at (x, y), anchored so the symbol does not move."""
    # Depth, 0 at the far edge of the canvas and 1 at the near edge.
    span = CANVAS - VP_Y
    u = ((y - VP_Y) / span - (0 - VP_Y) / span) / (1 - (0 - VP_Y) / span)
    u = min(max(u, 0.0), 1.0)

    s = lerp(FAR_SCALE, NEAR_SCALE, u)
    squash = lerp(FAR_SQUASH, 1.0, u)
    # Lean grows with distance from the vanishing point's column, and fades as
    # the symbol comes near — directly underfoot there is nothing to lean.
    shear = SHEAR * ((x - VP_X) / (CANVAS / 2)) * (1 - u)
    # Deterministic, so re-running gives the same field.
    theta = JITTER * math.sin(x * 0.021 + y * 0.017)

    cos, sin = math.cos(theta), math.sin(theta)
    a = s * cos + s * shear * sin
    b = s * squash * sin
    c = -s * sin + s * shear * cos
    d = s * squash * cos
    # Anchor at (x, y): translate so that point maps to itself.
    e = x - (a * x + c * y)
    f = y - (b * x + d * y)
    return a, b, c, d, e, f, s, u


def rewrite(text, apply=True):
    report = []

    def one(m):
        tag = m.group(0)
        x = _num(tag, r'<text[^>]*?\sx="([\d.-]+)"')
        y = _num(tag, r'<text[^>]*?\sy="([\d.-]+)"')
        if x is None or y is None:
            return tag

        base_op = _num(tag, r'data-base-op="([\d.]+)"')
        if base_op is None:
            base_op = _num(tag, r"opacity:\s*([\d.]+)", r'opacity="([\d.]+)"')
        if base_op is None:
            base_op = 1.0

        a, b, c, d, e, f, s, u = perspective(x, y)
        op = min(base_op * lerp(FAR_FADE, NEAR_FADE, u), 1.0)
        report.append((y, x, s, u, op))
        if not apply:
            return tag

        out = tag
        out = re.sub(
            r'transform="[^"]*"',
            'transform="matrix(%s)"'
            % ", ".join("%.6f" % v for v in (a, b, c, d, e, f)),
            out,
        )
        out = re.sub(r'\sopacity="[\d.]+"', ' opacity="%.3f"' % op, out)
        out = re.sub(r"opacity:\s*[\d.]+", "opacity: %.3f" % op, out)
        out = re.sub(r'\sdata-base-op="[\d.]+"', "", out)
        return out[:-1].rstrip() + ' data-base-op="%.3f">' % base_op

    return TEXT.sub(one, text), report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    files = args.files or sorted(glob.glob("assets/imgs/background_*.svg"))

    for path in files:
        text = io.open(path, encoding="utf-8").read()
        out, report = rewrite(text, apply=not args.check)
        name = path.replace("\\", "/").split("/")[-1]
        if not report:
            print("%s: no symbols found" % name)
            continue
        report.sort()
        far, near = report[0], report[-1]
        print(
            "%s: %d symbols   far y=%.0f scale %.2f opacity %.2f   "
            "near y=%.0f scale %.2f opacity %.2f"
            % (name, len(report), far[0], far[2], far[4],
               near[0], near[2], near[4])
        )
        if not args.check:
            io.open(path, "w", encoding="utf-8", newline="").write(out)


if __name__ == "__main__":
    main()
