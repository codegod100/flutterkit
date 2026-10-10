#!/usr/bin/env python3
"""Renders preview.png from the generated themes, laying the SVG pieces
out the way Aurorae does (a nine-slice frame plus buttons) with Qt's own
SVG renderer. Needs PySide6:

    QT_QPA_PLATFORM=offscreen python3 kde/aurorae/preview.py
"""

from pathlib import Path

from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QFont, QFontDatabase, QGuiApplication, QImage, QPainter
from PySide6.QtSvg import QSvgRenderer

HERE = Path(__file__).resolve().parent
PAD, BUTTON, EDGE_TOP, TITLE = 16, 24, 7, 24
W, H = 460, 200


def frame(p, r, prefix, x, y, w, h):
    """Paints a KSvg-style frame: corners at size, edges and centre stretched."""
    tl = r.boundsOnElement(f"{prefix}-topleft")
    br = r.boundsOnElement(f"{prefix}-bottomright")
    l, t, rr, b = tl.width(), tl.height(), br.width(), br.height()
    cells = {
        "topleft": (x, y, l, t), "top": (x + l, y, w - l - rr, t), "topright": (x + w - rr, y, rr, t),
        "left": (x, y + t, l, h - t - b), "center": (x + l, y + t, w - l - rr, h - t - b),
        "right": (x + w - rr, y + t, rr, h - t - b),
        "bottomleft": (x, y + h - b, l, b), "bottom": (x + l, y + h - b, w - l - rr, b),
        "bottomright": (x + w - rr, y + h - b, rr, b),
    }
    for name, rect in cells.items():
        if r.elementExists(f"{prefix}-{name}"):
            r.render(p, f"{prefix}-{name}", QRectF(*rect))


def window(p, theme, ox, oy, active, hover=None, content="#FFFFFF"):
    deco = QSvgRenderer(str(theme / "decoration.svg"))
    prefix = "decoration" if active else "decoration-inactive"
    frame(p, deco, prefix, ox, oy, W + 2 * PAD, H + 2 * PAD)
    border = 1
    title = TITLE + 2 * EDGE_TOP
    # Client area and the line under the title bar.
    client = QRectF(ox + PAD + border, oy + PAD + title, W - 2 * border, H - title - border)
    p.fillRect(client, QColor(content))
    ib = "innerborder" if active else "innerborder-inactive"
    frame(p, deco, ib, client.x() - 1, client.y() - 1, client.width() + 2, client.height() + 2)
    # Buttons on the right: minimize, maximize, close.
    bx = ox + PAD + W - EDGE_TOP - 3 * BUTTON - 2 * 4
    by = oy + PAD + EDGE_TOP
    for kind in ["minimize", "maximize", "close"]:
        r = QSvgRenderer(str(theme / f"{kind}.svg"))
        state = ("hover" if hover == kind else "active") + ("" if active else "-inactive")
        if state == "active-inactive":
            state = "inactive"
        r.render(p, f"{state}-center", QRectF(bx, by, BUTTON, BUTTON))
        bx += BUTTON + 4
    rc = (theme / f"{theme.name}rc").read_text()
    key = "ActiveTextColor=" if active else "InactiveTextColor="
    rgb = [int(v) for v in rc.split(key)[1].split("\n")[0].split(",")]
    p.setPen(QColor(*rgb))
    font = QFont("Inter")
    font.setPixelSize(13)
    font.setWeight(QFont.Weight.DemiBold)
    p.setFont(font)
    p.drawText(QRectF(ox + PAD, by, W, TITLE), Qt.AlignmentFlag.AlignCenter,
               theme.name.replace("-", " ") + ("" if active else " (inactive)"))


THEMES = [("Flatkit", "#E4E4E8", "#F6F6F7"), ("Flatkit-Dark", "#0E0E10", "#1C1C1F")]


def render(themes, out):
    """Draws each theme as a column: active window above, inactive below."""
    cell_w, cell_h = W + 2 * PAD + 8, H + 2 * PAD + 8
    img = QImage(len(themes) * cell_w + 16, 2 * cell_h + 16, QImage.Format.Format_ARGB32)
    p = QPainter(img)
    p.setRenderHint(QPainter.RenderHint.Antialiasing)
    for col, (name, page, content) in enumerate(themes):
        x = 8 + col * cell_w
        last = col == len(themes) - 1
        p.fillRect(QRectF(x - 8 if col == 0 else x, 0, cell_w + (16 if last else 8), img.height()), QColor(page))
        theme = HERE / "themes" / name
        window(p, theme, x, 8, True, hover="close", content=content)
        window(p, theme, x, 8 + cell_h, False, hover="maximize", content=content)
    p.end()
    out.parent.mkdir(exist_ok=True)
    img.save(str(out))
    print("wrote", out)


def main():
    app = QGuiApplication([])  # noqa: F841
    QFontDatabase.addApplicationFont(str(HERE.parent.parent / "fonts" / "Inter-SemiBold.ttf"))
    render(THEMES, HERE / "preview.png")
    # One screenshot per theme for the KDE Store pages.
    for t in THEMES:
        render([t], HERE / "store" / f"{t[0]}.png")


if __name__ == "__main__":
    main()
