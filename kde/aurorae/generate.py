#!/usr/bin/env python3
"""Generates the Flatkit Aurorae window decorations for KDE Plasma.

Colours and radii mirror lib/src/theme.dart (KitColors.light/.dark,
kitRadius). Run it after changing either; it rewrites themes/.

    python3 kde/aurorae/generate.py
"""

from pathlib import Path

OUT = Path(__file__).resolve().parent / "themes"

# KitColors, as #RRGGBB plus an alpha for the shadow.
LIGHT = dict(
    background="#F6F6F7", hover="#EDEDEF", pressed="#DEDEE2",
    border="#DADADE", borderStrong="#B8B8BF", text="#1E1E22",
    textDim="#66666E", danger="#D12D3A", dangerHover="#B8232F",
    onDanger="#FFFFFF", shadow=0.20, shadowInactive=0.11,
)
DARK = dict(
    background="#1C1C1F", hover="#323237", pressed="#3C3C42",
    border="#3A3A40", borderStrong="#55555D", text="#EDEDF0",
    textDim="#A0A0A8", danger="#E5484D", dangerHover="#EC5F63",
    onDanger="#FFFFFF", shadow=0.45, shadowInactive=0.28,
)

PAD = 16          # shadow padding around the window
RADIUS = 10       # top corners, the kit's dialog radius
C = PAD + RADIUS  # corner slice size
EDGE = 8          # length of the stretchable edge slices
BUTTON = 24       # KitIconButton.compact
BUTTON_RADIUS = 6 # kitRadius
GLYPH_STROKE = 1.5

# A gaussian-ish falloff for the shadow, as (offset, fraction of max alpha).
SHADOW_STOPS = [(0, 1.0), (0.15, 0.72), (0.35, 0.40), (0.6, 0.15), (0.8, 0.05), (1, 0)]


def stops(color, alpha):
    return "".join(
        f'<stop offset="{o}" stop-color="{color}" stop-opacity="{alpha * f:.3f}"/>'
        for o, f in SHADOW_STOPS
    )


def svg(width, height, defs, body):
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">\n<defs>{defs}</defs>\n{body}\n</svg>\n'
    )


def frame_set(prefix, x0, y0, c, alpha, defs):
    """The nine slices of one window frame, laid out from (x0, y0).

    The slices together draw: a soft shadow, the window's 1px outline in
    the border colour, and the title bar fill. Top corners are rounded;
    the bottom ones are square because the client window covers them.
    """
    bg, line = c["background"], c["border"]
    g = []
    gid = prefix.replace("-", "_")

    # Shadow gradients. Radial ones are centred on the corner arc so the
    # falloff follows the rounded outline.
    defs.append(
        f'<radialGradient id="{gid}_tl" gradientUnits="userSpaceOnUse" cx="{x0 + C}" cy="{y0 + C}" r="{C}">'
        + _radial_stops(c["shadow_color"], alpha, RADIUS / C) + "</radialGradient>"
    )
    defs.append(
        f'<radialGradient id="{gid}_tr" gradientUnits="userSpaceOnUse" cx="{x0 + C + EDGE}" cy="{y0 + C}" r="{C}">'
        + _radial_stops(c["shadow_color"], alpha, RADIUS / C) + "</radialGradient>"
    )
    by = y0 + C + EDGE  # top of the bottom row
    defs.append(
        f'<radialGradient id="{gid}_bl" gradientUnits="userSpaceOnUse" cx="{x0 + PAD}" cy="{by + RADIUS}" r="{PAD}">'
        + stops(c["shadow_color"], alpha) + "</radialGradient>"
    )
    defs.append(
        f'<radialGradient id="{gid}_br" gradientUnits="userSpaceOnUse" cx="{x0 + C + EDGE + RADIUS}" cy="{by + RADIUS}" r="{PAD}">'
        + stops(c["shadow_color"], alpha) + "</radialGradient>"
    )
    for name, (x1, y1, x2, y2) in {
        "t": (0, 1, 0, 0), "b": (0, 0, 0, 1), "l": (1, 0, 0, 0), "r": (0, 0, 1, 0),
    }.items():
        defs.append(
            f'<linearGradient id="{gid}_{name}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
            + stops(c["shadow_color"], alpha) + "</linearGradient>"
        )

    def el(name, x, y, w, h, content):
        # A transparent rect pins each element's bounding box to its slice.
        g.append(
            f'<g id="{prefix}-{name}"><rect x="{x}" y="{y}" width="{w}" height="{h}" '
            f'fill="#000" fill-opacity="0"/>{content}</g>'
        )

    # Top-left: shadow quarter ring, then the rounded corner with outline.
    x, y = x0, y0
    el("topleft", x, y, C, C,
       f'<rect x="{x}" y="{y}" width="{C}" height="{C}" fill="url(#{gid}_tl)"/>'
       f'<path d="M{x + PAD},{y + C} A{RADIUS},{RADIUS} 0 0 1 {x + C},{y + PAD} V{y + C} Z" fill="{line}"/>'
       f'<path d="M{x + PAD + 1},{y + C} A{RADIUS - 1},{RADIUS - 1} 0 0 1 {x + C},{y + PAD + 1} V{y + C} Z" fill="{bg}"/>')
    # Top edge.
    x = x0 + C
    el("top", x, y, EDGE, C,
       f'<rect x="{x}" y="{y}" width="{EDGE}" height="{PAD}" fill="url(#{gid}_t)"/>'
       f'<rect x="{x}" y="{y + PAD}" width="{EDGE}" height="1" fill="{line}"/>'
       f'<rect x="{x}" y="{y + PAD + 1}" width="{EDGE}" height="{RADIUS - 1}" fill="{bg}"/>')
    # Top-right, mirrored.
    x = x0 + C + EDGE
    el("topright", x, y, C, C,
       f'<rect x="{x}" y="{y}" width="{C}" height="{C}" fill="url(#{gid}_tr)"/>'
       f'<path d="M{x},{y + C} V{y + PAD} A{RADIUS},{RADIUS} 0 0 1 {x + RADIUS},{y + C} Z" fill="{line}"/>'
       f'<path d="M{x},{y + C} V{y + PAD + 1} A{RADIUS - 1},{RADIUS - 1} 0 0 1 {x + RADIUS - 1},{y + C} Z" fill="{bg}"/>')

    # Middle row.
    y = y0 + C
    x = x0
    el("left", x, y, C, EDGE,
       f'<rect x="{x}" y="{y}" width="{PAD}" height="{EDGE}" fill="url(#{gid}_l)"/>'
       f'<rect x="{x + PAD}" y="{y}" width="1" height="{EDGE}" fill="{line}"/>'
       f'<rect x="{x + PAD + 1}" y="{y}" width="{RADIUS - 1}" height="{EDGE}" fill="{bg}"/>')
    x = x0 + C
    el("center", x, y, EDGE, EDGE, f'<rect x="{x}" y="{y}" width="{EDGE}" height="{EDGE}" fill="{bg}"/>')
    x = x0 + C + EDGE
    el("right", x, y, C, EDGE,
       f'<rect x="{x}" y="{y}" width="{RADIUS - 1}" height="{EDGE}" fill="{bg}"/>'
       f'<rect x="{x + RADIUS - 1}" y="{y}" width="1" height="{EDGE}" fill="{line}"/>'
       f'<rect x="{x + RADIUS}" y="{y}" width="{PAD}" height="{EDGE}" fill="url(#{gid}_r)"/>')

    # Bottom row: square corners.
    y = y0 + C + EDGE
    x = x0
    el("bottomleft", x, y, C, C,
       f'<rect x="{x}" y="{y}" width="{PAD}" height="{RADIUS}" fill="url(#{gid}_l)"/>'
       f'<rect x="{x + PAD}" y="{y + RADIUS}" width="{RADIUS}" height="{PAD}" fill="url(#{gid}_b)"/>'
       f'<rect x="{x}" y="{y + RADIUS}" width="{PAD}" height="{PAD}" fill="url(#{gid}_bl)"/>'
       f'<rect x="{x + PAD}" y="{y}" width="{RADIUS}" height="{RADIUS}" fill="{line}"/>'
       f'<rect x="{x + PAD + 1}" y="{y}" width="{RADIUS - 1}" height="{RADIUS - 1}" fill="{bg}"/>')
    x = x0 + C
    el("bottom", x, y, EDGE, C,
       f'<rect x="{x}" y="{y}" width="{EDGE}" height="{RADIUS - 1}" fill="{bg}"/>'
       f'<rect x="{x}" y="{y + RADIUS - 1}" width="{EDGE}" height="1" fill="{line}"/>'
       f'<rect x="{x}" y="{y + RADIUS}" width="{EDGE}" height="{PAD}" fill="url(#{gid}_b)"/>')
    x = x0 + C + EDGE
    el("bottomright", x, y, C, C,
       f'<rect x="{x + RADIUS}" y="{y}" width="{PAD}" height="{RADIUS}" fill="url(#{gid}_r)"/>'
       f'<rect x="{x}" y="{y + RADIUS}" width="{RADIUS}" height="{PAD}" fill="url(#{gid}_b)"/>'
       f'<rect x="{x + RADIUS}" y="{y + RADIUS}" width="{PAD}" height="{PAD}" fill="url(#{gid}_br)"/>'
       f'<rect x="{x}" y="{y}" width="{RADIUS}" height="{RADIUS}" fill="{line}"/>'
       f'<rect x="{x}" y="{y}" width="{RADIUS - 1}" height="{RADIUS - 1}" fill="{bg}"/>')
    return g


def _radial_stops(color, alpha, start):
    # Transparent inside the arc, then the shadow falloff from the outline out.
    out = f'<stop offset="0" stop-color="{color}" stop-opacity="0"/>'
    out += f'<stop offset="{start - 0.001:.4f}" stop-color="{color}" stop-opacity="0"/>'
    for o, f in SHADOW_STOPS:
        out += f'<stop offset="{start + (1 - start) * o:.4f}" stop-color="{color}" stop-opacity="{alpha * f:.3f}"/>'
    return out


def decoration_svg(c):
    defs, body = [], []
    span = 2 * C + EDGE + 20
    body += frame_set("decoration", 0, 0, c, c["shadow"], defs)
    body += frame_set("decoration-inactive", span, 0, c, c["shadowInactive"], defs)
    y = span
    # Maximized: no shadow, no outline, just the title bar fill.
    for i, prefix in enumerate(["decoration-maximized", "decoration-maximized-inactive"]):
        x = i * 20
        body.append(
            f'<g id="{prefix}-center"><rect x="{x}" y="{y}" width="{EDGE}" height="{EDGE}" fill="{c["background"]}"/></g>'
        )
    # A 1px line under the title bar: the top of a frame drawn around the
    # client area. The other three sides are transparent so the border
    # setting's own fill shows there.
    y += 20
    line = c["border"]
    for i, prefix in enumerate(["innerborder", "innerborder-inactive"]):
        x = i * 20
        parts = {
            "topleft": (x, y, 1, 1, line), "top": (x + 1, y, 1, 1, line), "topright": (x + 2, y, 1, 1, line),
            "left": (x, y + 1, 1, 1, None), "right": (x + 2, y + 1, 1, 1, None),
            "bottomleft": (x, y + 2, 1, 1, None), "bottom": (x + 1, y + 2, 1, 1, None),
            "bottomright": (x + 2, y + 2, 1, 1, None),
        }
        for name, (px, py, w, h, fill) in parts.items():
            paint = f'fill="{fill}"' if fill else 'fill="#000" fill-opacity="0"'
            body.append(f'<g id="{prefix}-{name}"><rect x="{px}" y="{py}" width="{w}" height="{h}" {paint}/></g>')
    width = 2 * span
    height = y + 10
    return svg(width, height, "".join(defs), "\n".join(body))


# Button glyphs, drawn on a 24px box with the stroke in currentColor-like
# substitution ({fg}). Shapes follow the kit's Material-style icons.
GLYPHS = {
    "close": '<path d="M8,8 L16,16 M16,8 L8,16" stroke="{fg}" stroke-width="{sw}" stroke-linecap="round" fill="none"/>',
    "minimize": '<path d="M7.5,12.5 H16.5" stroke="{fg}" stroke-width="{sw}" stroke-linecap="round" fill="none"/>',
    "maximize": '<rect x="7.75" y="7.75" width="8.5" height="8.5" rx="1.5" stroke="{fg}" stroke-width="{sw}" fill="none"/>',
    "restore": (
        '<rect x="7.25" y="9.25" width="7.5" height="7.5" rx="1.5" stroke="{fg}" stroke-width="{sw}" fill="none"/>'
        '<path d="M9.75,7 H15.5 Q17,7 17,8.5 V14.25" stroke="{fg}" stroke-width="{sw}" stroke-linecap="round" fill="none"/>'
    ),
    "keepabove": '<path d="M8,13.5 L12,9.5 L16,13.5" stroke="{fg}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
    "keepbelow": '<path d="M8,10.5 L12,14.5 L16,10.5" stroke="{fg}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
    "alldesktops": (
        '<circle cx="12" cy="12" r="4.25" stroke="{fg}" stroke-width="{sw}" fill="none"/>'
        '<circle cx="12" cy="12" r="1.5" fill="{fg}"/>'
    ),
    "shade": '<path d="M7.5,9 H16.5 M8,13.5 L12,16.5 L16,13.5" stroke="{fg}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>',
    "help": (
        '<path d="M9.5,10 Q9.5,7.5 12,7.5 Q14.5,7.5 14.5,9.75 Q14.5,11.25 12.75,12 Q12,12.4 12,13.5" '
        'stroke="{fg}" stroke-width="{sw}" stroke-linecap="round" fill="none"/>'
        '<circle cx="12" cy="16.25" r="1" fill="{fg}"/>'
    ),
}


def button_svg(kind, c):
    """One button with every state Aurorae looks for, side by side.

    Matches KitIconButton: no background at rest, the hover colour on
    hover and the pressed colour while held, 6px corners. Close turns
    red on hover like the kit's danger button.
    """
    danger = kind == "close"
    states = [
        ("active", None, c["text"]),
        ("hover", c["danger"] if danger else c["hover"], c["onDanger"] if danger else c["text"]),
        ("pressed", c["dangerHover"] if danger else c["pressed"], c["onDanger"] if danger else c["text"]),
        ("inactive", None, c["textDim"]),
        ("hover-inactive", c["danger"] if danger else c["hover"], c["onDanger"] if danger else c["text"]),
        ("pressed-inactive", c["dangerHover"] if danger else c["pressed"], c["onDanger"] if danger else c["text"]),
        ("deactivated", None, c["borderStrong"]),
        ("deactivated-inactive", None, c["borderStrong"]),
    ]
    body = []
    for i, (state, bg, fg) in enumerate(states):
        x = i * (BUTTON + 4)
        inner = GLYPHS[kind].format(fg=fg, sw=GLYPH_STROKE)
        back = (
            f'<rect width="{BUTTON}" height="{BUTTON}" rx="{BUTTON_RADIUS}" fill="{bg}"/>' if bg
            else f'<rect width="{BUTTON}" height="{BUTTON}" fill="#000" fill-opacity="0"/>'
        )
        body.append(f'<g id="{state}-center" transform="translate({x},0)">{back}{inner}</g>')
    return svg(len(states) * (BUTTON + 4), BUTTON, "", "\n".join(body))


def rc(c):
    return f"""[General]
ActiveTextColor={hex_rgb(c["text"])}
InactiveTextColor={hex_rgb(c["textDim"])}
TitleAlignment=Center
TitleVerticalAlignment=Center
Animation=0
Shadow=true
UseTextShadow=false
DecorationPosition=0

[Layout]
BorderLeft=1
BorderRight=1
BorderBottom=1
BorderTop=1
TitleEdgeTop=7
TitleEdgeBottom=7
TitleEdgeLeft=7
TitleEdgeRight=7
TitleEdgeTopMaximized=5
TitleEdgeBottomMaximized=5
TitleEdgeLeftMaximized=5
TitleEdgeRightMaximized=5
TitleBorderLeft=8
TitleBorderRight=8
TitleHeight=24
ButtonWidth={BUTTON}
ButtonHeight={BUTTON}
ButtonSpacing=4
ButtonMarginTop=0
ButtonMarginTopMaximized=0
ExplicitButtonSpacer=8
PaddingTop={PAD}
PaddingBottom={PAD}
PaddingLeft={PAD}
PaddingRight={PAD}
"""


def hex_rgb(h):
    return ",".join(str(int(h[i:i + 2], 16)) for i in (1, 3, 5))


def metadata(name, plugin, description):
    return f"""[Desktop Entry]
Name={name}
Comment={description}
X-KDE-PluginInfo-Author=codegod100
X-KDE-PluginInfo-Name={plugin}
X-KDE-PluginInfo-Version=1.0
X-KDE-PluginInfo-Website=https://github.com/codegod100/flutterkit
X-KDE-PluginInfo-Category=
X-KDE-PluginInfo-License=MIT
X-KDE-PluginInfo-EnabledByDefault=true
X-Plasma-API=javascript
X-KDE-ServiceTypes=KWin/Decoration
"""


def main():
    for name, colors in [("Flatkit", LIGHT), ("Flatkit-Dark", DARK)]:
        c = dict(colors, shadow_color="#000000")
        d = OUT / name
        d.mkdir(parents=True, exist_ok=True)
        (d / "decoration.svg").write_text(decoration_svg(c))
        for kind in GLYPHS:
            (d / f"{kind}.svg").write_text(button_svg(kind, c))
        (d / f"{name}rc").write_text(rc(c))
        pretty = name.replace("-", " ")
        (d / "metadata.desktop").write_text(
            metadata(pretty, name, f"Flat window decoration matching the flatkit Flutter widgets ({'dark' if 'Dark' in name else 'light'})")
        )
        print("wrote", d)


if __name__ == "__main__":
    main()
