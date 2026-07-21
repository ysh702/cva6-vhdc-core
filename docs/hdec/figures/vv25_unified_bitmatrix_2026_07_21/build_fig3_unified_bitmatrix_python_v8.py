from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyArrowPatch, Rectangle
from PIL import Image


plt.rcParams.update(
    {
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "DejaVu Sans", "Liberation Sans"],
        "svg.fonttype": "none",
        "pdf.fonttype": 42,
        "font.size": 7.0,
        "hatch.linewidth": 0.30,
    }
)


OUT_DIR = Path(__file__).resolve().parent
OUT_STEM = OUT_DIR / "HDEC_Fig3_unified_bitmatrix_python_v8"


C = {
    "white": "#FFFFFF",
    "ink": "#202124",
    "text2": "#5F6368",
    "line": "#8B9197",
    "light": "#BCC2C7",
    "faint": "#E1E4E6",
    "inactive": "#D9DDE0",
    "bit0": "#C8CDD1",
    "bit1": "#34383C",
    # Three restrained semantic accents.  Geometry remains legible in greyscale.
    "ecc": "#496B83",       # ECC-specific reverse/alignment relation
    "unified": "#655E86",   # fixed mapping and shared 8x32 data type
    "and": "#8A6548",       # pointwise AND and its result
    "ecc_light": "#E7EDF1",
    "unified_light": "#ECEAF1",
    "and_light": "#F0EBE7",
}


def arrow(ax, x0, y0, x1, y1, *, color=None, lw=0.85, ms=7.0, z=20):
    color = color or C["ink"]
    p = FancyArrowPatch(
        (x0, y0),
        (x1, y1),
        arrowstyle="-|>",
        mutation_scale=ms,
        linewidth=lw,
        color=color,
        shrinkA=0,
        shrinkB=0,
        capstyle="butt",
        joinstyle="miter",
        zorder=z,
    )
    ax.add_patch(p)
    return p


def stage_title(ax, x, number, title):
    ax.text(x - 0.9, 73.35, number, ha="right", va="center", fontsize=7.0, fontweight="normal", color=C["line"])
    ax.text(x, 73.35, title, ha="left", va="center", fontsize=7.2, fontweight="normal", color=C["ink"])


def draw_token_row(
    ax,
    centers,
    y,
    labels,
    *,
    row_label,
    edge=None,
    fill=None,
    text_color=None,
    w=2.85,
    h=2.05,
    z=10,
    highlight_indices=None,
    highlight_color=None,
):
    edge = edge or C["ink"]
    fill = fill or C["white"]
    text_color = text_color or C["ink"]
    highlight_indices = set(highlight_indices or [])
    highlight_color = highlight_color or C["unified"]
    ax.text(centers[0] - w / 2 - 1.05, y, row_label, ha="right", va="center", fontsize=7.0, fontweight="bold", color=C["ink"])
    for idx, (x, label) in enumerate(zip(centers, labels)):
        active = idx in highlight_indices
        token_edge = highlight_color if active else edge
        token_fill = C["unified_light"] if active else fill
        token_text = highlight_color if active else text_color
        ax.add_patch(Rectangle((x - w / 2, y - h / 2), w, h, facecolor=token_fill, edgecolor=token_edge, linewidth=0.92 if active else 0.72, zorder=z))
        ax.text(x, y, label, ha="center", va="center", fontsize=6.5, color=token_text, fontweight="bold" if active else "normal", zorder=z + 1)


def draw_pair_lines(
    ax,
    xs_top,
    y_top,
    xs_bottom,
    y_bottom,
    *,
    color=None,
    highlight=None,
    highlight_color=None,
    lw=0.55,
):
    color = color or C["line"]
    highlight_color = highlight_color or C["unified"]
    for idx, (xa, xb) in enumerate(zip(xs_top, xs_bottom)):
        col = highlight_color if highlight is not None and idx == highlight else color
        width = 1.15 if highlight is not None and idx == highlight else lw
        ax.plot([xa, xb], [y_top - 1.04, y_bottom + 1.04], color=col, lw=width, zorder=5)


def draw_partition_row(ax, x, y, *, label):
    n, w, gap, h = 8, 1.65, 0.34, 1.72
    ax.text(x - 1.0, y, label, ha="right", va="center", fontsize=7.0, fontweight="bold", color=C["ink"])
    for idx in range(n):
        xx = x + idx * (w + gap)
        ax.add_patch(
            Rectangle(
                (xx, y - h / 2),
                w,
                h,
                facecolor=C["white"],
                edgecolor=C["ink"],
                linewidth=0.60,
                zorder=8,
            )
        )
        ax.plot([xx + 0.42, xx + w - 0.42], [y, y], color=C["light"], lw=0.50, zorder=9)
    return x + n * w + (n - 1) * gap


def draw_fiber_loom(ax, x, y, w, h, *, label, bits):
    """Sample six columns from an actual 8x32 operand, before bracket packing."""
    ax.text(x + w / 2, y + h + 1.10, label, ha="center", va="bottom", fontsize=7.0, fontweight="bold", color=C["ink"])
    sample_cols = (0, 6, 12, 18, 24, 31)
    for r in range(8):
        yy = y + h - (r + 0.5) * h / 8
        ax.plot([x, x + w], [yy, yy], color=C["line"], lw=0.52, zorder=5)
        for sample_idx, c in enumerate(sample_cols):
            xx = x + 0.55 + sample_idx * (w - 1.10) / 5
            filled = bits[r][c]
            ax.plot(
                xx,
                yy,
                marker="s" if filled else "o",
                markersize=1.85 if filled else 1.65,
                markerfacecolor=C["bit1"] if filled else C["white"],
                markeredgecolor=C["bit1"] if filled else C["light"],
                markeredgewidth=0.38,
                zorder=7,
            )
    # Sparse coordinate ticks establish two axes without a grid.
    for frac in (0.0, 0.5, 1.0):
        xx = x + frac * w
        ax.plot([xx, xx], [y - 0.25, y + 0.25], color=C["line"], lw=0.45)


def draw_shift_field(ax, x0=54.0, pitch=0.815, *, a_word=0xB35D, b_word=0xD6A7):
    """Show A replication and align real A/B_rev pairs directly by diagonal k."""
    rows = [(0, 30.0), (1, 25.6), (3, 21.2), (15, 13.6)]
    diagonal_x = x0 + 15 * pitch

    # The vertical guide is a coordinate relation, not data and not an operator.
    ax.plot(
        [diagonal_x, diagonal_x],
        [12.65, 31.0],
        color=C["ecc"],
        lw=0.72,
        linestyle=(0, (2.0, 1.8)),
        zorder=2,
    )
    ax.text(
        x0 + 15 * pitch,
        35.3,
        r"16 copies of each $a_i$",
        ha="center",
        va="center",
        fontsize=6.2,
        fontweight="bold",
        color=C["unified"],
    )

    for i, y in rows:
        ax.text(x0 - 0.65, y, rf"$i={i}$", ha="right", va="center", fontsize=6.1, color=C["unified"] if i == 3 else C["ink"])
        valid_lo = i
        valid_hi = i + 15
        ax.plot(
            [x0 + valid_lo * pitch, x0 + valid_hi * pitch],
            [y, y],
            color=C["light"],
            lw=0.42,
            zorder=3,
        )

        a_bit = bool((a_word >> i) & 1)
        for t in range(16):
            pos = 15 + i - t
            xx = x0 + pos * pitch
            # B_rev[t] = B[15-t].  The two bit glyphs remain separate until
            # the one shared pointwise AND in Stage 4.
            b_rev_bit = bool((b_word >> (15 - t)) & 1)
            ax.plot([xx, xx], [y - 0.17, y + 0.17], color=C["line"], lw=0.34, zorder=5)
            ax.plot(
                xx,
                y + 0.23,
                marker="s" if a_bit else "o",
                markersize=1.62 if a_bit else 1.42,
                markerfacecolor=C["bit1"] if a_bit else C["white"],
                markeredgecolor=C["bit1"] if a_bit else C["bit0"],
                markeredgewidth=0.36,
                zorder=7,
            )
            ax.plot(
                xx,
                y - 0.23,
                marker="s" if b_rev_bit else "o",
                markersize=1.62 if b_rev_bit else 1.42,
                markerfacecolor=C["bit1"] if b_rev_bit else C["white"],
                markeredgecolor=C["bit1"] if b_rev_bit else C["bit0"],
                markeredgewidth=0.36,
                zorder=7,
            )
            # Trace all sixteen copies of a_3, rather than selecting one
            # product.  The same sixteen copies are ringed after fixed packing.
            if i == 3:
                ax.add_patch(
                    Circle(
                        (xx, y + 0.23),
                        0.185,
                        facecolor="none",
                        edgecolor=C["unified"],
                        linewidth=0.68,
                        zorder=8,
                    )
                )

    ax.text(x0 - 0.9, 17.4, r"$\vdots$", ha="center", va="center", fontsize=10.0, color=C["text2"])
    ax.text(
        diagonal_x,
        32.0,
        r"$k=15$",
        ha="center",
        va="bottom",
        fontsize=6.4,
        fontweight="bold",
        color=C["ecc"],
    )
    ax.text(x0 + 15 * pitch + 0.48, rows[0][1] + 0.95, r"$A^{(E)}$", ha="left", va="center", fontsize=5.6, color=C["ink"])
    ax.text(x0 + 15 * pitch + 0.48, rows[0][1] - 1.25, r"$B_{\mathrm{rev}}^{(E)}$", ha="left", va="center", fontsize=5.6, color=C["ink"])
    ax.text(
        x0 + 15 * pitch,
        10.7,
        r"$k=i+j=15+i-t$",
        ha="center",
        va="center",
        fontsize=6.4,
        fontweight="bold",
        color=C["ink"],
    )


def make_bits(seed):
    bits = []
    for r in range(8):
        row = []
        for c in range(32):
            v = ((r * 11 + c * 7 + seed * 5 + (r ^ c)) % 13) in (0, 1, 3, 7)
            row.append(bool(v))
        bits.append(row)
    # One representative coordinate is deliberately 1 in all operand matrices.
    bits[3][18] = True
    return bits


def diag_len(diag):
    return diag + 1 if diag < 16 else 31 - diag


def build_vv25_layout():
    """Frozen R31 8x32 order as (diagonal, term-within-diagonal)."""
    layout = []
    for short_len in range(1, 8):
        lower_short = short_len - 1
        lower_long = 15 - short_len
        upper_short = 31 - short_len
        upper_long = 15 + short_len
        layout.extend((lower_long, term) for term in range(8))
        layout.extend((lower_short, term) for term in range(short_len))
        layout.extend((lower_long, term) for term in range(8, diag_len(lower_long)))
        layout.extend((upper_long, term) for term in range(8))
        layout.extend((upper_short, term) for term in range(short_len))
        layout.extend((upper_long, term) for term in range(8, diag_len(upper_long)))
    layout.extend((7, term) for term in range(8))
    layout.extend((23, term) for term in range(8))
    layout.extend((15, term) for term in range(8))
    layout.extend((15, term) for term in range(8, 16))
    expected = {
        (diag, term)
        for diag in range(31)
        for term in range(diag_len(diag))
    }
    assert len(layout) == 256
    assert len(set(layout)) == 256
    assert set(layout) == expected
    return layout


VV25_LAYOUT = build_vv25_layout()


def grid_coords_for_a_index(a_index):
    coords = []
    for flat, (diag, term) in enumerate(VV25_LAYOUT):
        i = max(0, diag - 15) + term
        if i == a_index:
            coords.append(divmod(flat, 32))
    assert len(coords) == 16
    return coords


def ecc_operand_bits(a_word, b_word):
    """Generate true VV25 operand matrices from one 16-bit ECC leaf."""
    a_bits = [[False for _ in range(32)] for _ in range(8)]
    b_bits = [[False for _ in range(32)] for _ in range(8)]
    for flat, (diag, term) in enumerate(VV25_LAYOUT):
        start_i = max(0, diag - 15)
        i = start_i + term
        j = diag - i
        r, c = divmod(flat, 32)
        a_bits[r][c] = bool((a_word >> i) & 1)
        b_bits[r][c] = bool((b_word >> j) & 1)
    return a_bits, b_bits


def and_bits(a, b):
    return [[bool(a[r][c] and b[r][c]) for c in range(32)] for r in range(8)]


def draw_bit_matrix(
    ax,
    x,
    y,
    w,
    h,
    bits,
    *,
    label,
    highlight=None,
    highlight_color=None,
    highlight_label=None,
    copy_highlights=None,
    copy_highlight_color=None,
    show_dim=False,
    label_position="left",
):
    """Bracketed 8×32 micro-dot field: matrix identity without a cell table."""
    highlight_color = highlight_color or C["unified"]
    copy_highlight_color = copy_highlight_color or C["unified"]
    cap = 0.78
    # Mathematical square brackets are the primary matrix cue.
    ax.plot([x, x, x + cap], [y, y + h, y + h], color=C["unified"], lw=0.92, zorder=12)
    ax.plot([x, x + cap], [y, y], color=C["unified"], lw=0.92, zorder=12)
    ax.plot([x + w, x + w, x + w - cap], [y, y + h, y + h], color=C["unified"], lw=0.92, zorder=12)
    ax.plot([x + w, x + w - cap], [y, y], color=C["unified"], lw=0.92, zorder=12)

    left, right = x + 1.00, x + w - 1.00
    xs = [left + c * (right - left) / 31 for c in range(32)]
    bottom, top = y + 0.38, y + h - 0.38
    ys = [top - r * (top - bottom) / 7 for r in range(8)]
    for hr, hc in copy_highlights or []:
        ax.add_patch(
            Circle(
                (xs[hc], ys[hr]),
                0.29,
                facecolor=C["unified_light"],
                edgecolor="none",
                alpha=0.88,
                zorder=12.5,
            )
        )
    for r, yy in enumerate(ys):
        for c, xx in enumerate(xs):
            if bits[r][c]:
                ax.plot(xx, yy, marker="s", markersize=1.65, markerfacecolor=C["bit1"], markeredgecolor=C["bit1"], markeredgewidth=0.20, zorder=14)
            else:
                ax.plot(xx, yy, marker="o", markersize=1.20, markerfacecolor=C["white"], markeredgecolor=C["bit0"], markeredgewidth=0.34, zorder=13)

    for hr, hc in copy_highlights or []:
        ax.add_patch(Circle((xs[hc], ys[hr]), 0.27, facecolor="none", edgecolor=copy_highlight_color, linewidth=0.74, zorder=17))

    if highlight is not None:
        hr, hc = highlight
        ax.add_patch(Circle((xs[hc], ys[hr]), 0.42, facecolor="none", edgecolor=highlight_color, linewidth=1.08, zorder=18))
        if highlight_label:
            ax.text(xs[hc], y - 0.68, highlight_label, ha="center", va="top", fontsize=5.8, color=highlight_color, zorder=19)
    if label_position == "above":
        ax.text(x + w / 2, y + h + 0.78, label, ha="center", va="bottom", fontsize=7.0, fontweight="bold", color=C["ink"])
    else:
        ax.text(x - 0.9, y + h / 2, label, ha="right", va="center", fontsize=7.0, fontweight="bold", color=C["ink"])

    if show_dim:
        # One compact dimension signature is enough for every identical glyph.
        ax.plot([x - 0.72, x - 0.72], [y + 0.15, y + h - 0.15], color=C["line"], lw=0.45)
        ax.plot([x - 0.95, x - 0.49], [y + 0.15, y + 0.15], color=C["line"], lw=0.45)
        ax.plot([x - 0.95, x - 0.49], [y + h - 0.15, y + h - 0.15], color=C["line"], lw=0.45)
        ax.text(x - 1.18, y + h / 2, "8", ha="right", va="center", fontsize=6.5, color=C["text2"])
        ax.plot([x + 0.2, x + w - 0.2], [y - 0.52, y - 0.52], color=C["line"], lw=0.45)
        ax.plot([x + 0.2, x + 0.2], [y - 0.75, y - 0.29], color=C["line"], lw=0.45)
        ax.plot([x + w - 0.2, x + w - 0.2], [y - 0.75, y - 0.29], color=C["line"], lw=0.45)
        ax.text(x + w / 2, y - 0.95, "32", ha="center", va="top", fontsize=6.5, color=C["text2"])


def build_figure():
    fig = plt.figure(figsize=(7.16, 4.0), facecolor=C["white"])
    ax = fig.add_axes([0.008, 0.012, 0.984, 0.976])
    ax.set_xlim(0, 140)
    ax.set_ylim(0, 78)
    ax.set_aspect("equal")
    ax.axis("off")

    # Pure white paper canvas.  Only alignment lines organize the argument.
    ax.plot([1.5, 138.5], [69.6, 69.6], color=C["ink"], lw=0.62)
    ax.plot([1.5, 138.5], [38.8, 38.8], color=C["light"], lw=0.52)
    ax.plot([1.5, 138.5], [8.0, 8.0], color=C["ink"], lw=0.52)
    for x in (26.5, 50.5, 81.5, 111.5):
        ax.plot([x, x], [9.2, 68.6], color=C["faint"], lw=0.48, linestyle=(0, (2.0, 2.2)))

    stage_title(ax, 5.0, "0", "Native index")
    stage_title(ax, 31.0, "1", "Index normalization")
    stage_title(ax, 57.0, "2", "Replicate and align")
    stage_title(ax, 87.0, "3", r"Unified bit matrix  $8\times32$")
    stage_title(ax, 119.0, "4", "Pointwise AND")

    # Lane titles stay neutral; the colored rules define the restrained semantics.
    ax.text(2.1, 66.0, "HDC", ha="left", va="center", fontsize=8.2, fontweight="bold", color=C["ink"])
    ax.plot([1.6, 1.6], [63.8, 68.2], color=C["ink"], lw=1.15)
    ax.text(2.1, 35.0, "ECC", ha="left", va="center", fontsize=8.2, fontweight="bold", color=C["ink"])
    ax.plot([1.6, 1.6], [32.8, 37.2], color=C["ecc"], lw=1.55)

    # ---------------------------------------------------------------
    # 0 — Native index relations.
    # ---------------------------------------------------------------
    xs0 = [6.3, 10.3, 14.3, 18.3, 22.3]
    draw_token_row(ax, xs0, 58.7, [r"$a_0$", r"$a_1$", r"$a_n$", r"$a_{254}$", r"$a_{255}$"], row_label=r"$A^{(H)}$")
    draw_token_row(ax, xs0, 51.1, [r"$b_0$", r"$b_1$", r"$b_n$", r"$b_{254}$", r"$b_{255}$"], row_label=r"$B^{(H)}$")
    draw_pair_lines(ax, xs0, 58.7, xs0, 51.1, color=C["line"])

    draw_token_row(
        ax,
        xs0,
        28.4,
        [r"$a_0$", r"$a_1$", r"$a_3$", r"$a_{14}$", r"$a_{15}$"],
        row_label=r"$A^{(E)}$",
        highlight_indices=[2],
    )
    draw_token_row(ax, xs0, 20.2, [r"$b_0$", r"$b_1$", r"$b_{12}$", r"$b_{14}$", r"$b_{15}$"], row_label=r"$B^{(E)}$")
    draw_pair_lines(
        ax,
        xs0,
        28.4,
        list(reversed(xs0)),
        20.2,
        color=C["ecc"],
        lw=0.48,
    )
    ax.text(14.3, 12.9, r"$k=i+j=15$", ha="center", va="center", fontsize=6.7, fontweight="bold", color=C["ink"])

    arrow(ax, 24.2, 58.7, 26.0, 58.7, color=C["line"])
    arrow(ax, 24.2, 51.1, 26.0, 51.1, color=C["line"])
    arrow(ax, 24.2, 28.4, 26.0, 28.4, color=C["line"])
    arrow(ax, 24.2, 20.2, 26.0, 20.2, color=C["ecc"])

    # ---------------------------------------------------------------
    # 1 — HDC partitions directly; ECC changes crossing to slotwise pairing.
    # ---------------------------------------------------------------
    xpart = 29.1
    end_part = draw_partition_row(ax, xpart, 58.1, label=r"$A^{(H)}$")
    draw_partition_row(ax, xpart, 51.4, label=r"$B^{(H)}$")
    for idx in (0, 3, 7):
        xx = xpart + idx * (1.65 + 0.34) + 0.825
        ax.plot([xx, xx], [52.28, 57.22], color=C["line"], lw=0.48)
    ax.plot([xpart, end_part], [47.9, 47.9], color=C["line"], lw=0.46)
    ax.plot([xpart, xpart], [47.6, 48.2], color=C["line"], lw=0.46)
    ax.plot([end_part, end_part], [47.6, 48.2], color=C["line"], lw=0.46)
    ax.text((xpart + end_part) / 2, 46.8, r"$8\times32$", ha="center", va="center", fontsize=6.8, fontweight="bold", color=C["ink"])

    xs1 = [30.4, 34.4, 38.4, 42.4, 46.4]
    draw_token_row(
        ax,
        xs1,
        28.0,
        [r"$a_0$", r"$a_1$", r"$a_3$", r"$a_{14}$", r"$a_{15}$"],
        row_label=r"$A^{(E)}$",
        highlight_indices=[2],
    )
    draw_token_row(
        ax,
        xs1,
        20.0,
        [r"$b_{15}$", r"$b_{14}$", r"$b_{12}$", r"$b_1$", r"$b_0$"],
        row_label=r"$B_{\mathrm{rev}}^{(E)}$",
    )
    draw_pair_lines(
        ax,
        xs1,
        28.0,
        xs1,
        20.0,
        color=C["ecc"],
        lw=0.54,
    )
    ax.text(
        38.4,
        12.2,
        r"$b_{\mathrm{rev},t}=b_{15-t}$",
        ha="center",
        va="center",
        fontsize=6.8,
        fontweight="bold",
        color=C["ink"],
    )

    arrow(ax, 48.3, 58.1, 52.2, 58.1, color=C["line"])
    arrow(ax, 48.3, 51.4, 52.2, 51.4, color=C["line"])
    # ---------------------------------------------------------------
    # 2 — Task-specific position layouts.  No product exists yet.
    # ---------------------------------------------------------------
    h_a, h_b = make_bits(1), make_bits(4)
    e_a, e_b = ecc_operand_bits(0xB35D, 0xD6A7)
    h_q, e_q = and_bits(h_a, h_b), and_bits(e_a, e_b)
    a3_cells = grid_coords_for_a_index(3)

    draw_fiber_loom(ax, 53.4, 50.7, 11.0, 9.1, label=r"$A^{(H)}$", bits=h_a)
    draw_fiber_loom(ax, 67.9, 50.7, 11.0, 9.1, label=r"$B^{(H)}$", bits=h_b)
    arrow(ax, 48.3, 24.0, 52.9, 24.0, color=C["ecc"], lw=0.72, ms=5.8)
    draw_shift_field(ax, a_word=0xB35D, b_word=0xD6A7)

    # Fixed packing maps branch once into the two same-shaped operand matrices.
    ax.plot([79.6, 81.1], [55.0, 55.0], color=C["unified"], lw=0.75)
    arrow(ax, 81.1, 55.0, 83.8, 60.1, color=C["unified"], lw=0.75, ms=6.2)
    arrow(ax, 81.1, 55.0, 83.8, 47.7, color=C["unified"], lw=0.75, ms=6.2)
    ax.text(81.0, 56.1, "fixed pack", ha="center", va="bottom", fontsize=5.3, fontweight="bold", color=C["unified"])

    ax.plot([79.6, 81.1], [24.0, 24.0], color=C["unified"], lw=0.75)
    arrow(ax, 81.1, 24.0, 83.8, 30.6, color=C["unified"], lw=0.75, ms=6.2)
    arrow(ax, 81.1, 24.0, 83.8, 18.2, color=C["unified"], lw=0.75, ms=6.2)
    ax.text(81.0, 25.1, "fixed pack", ha="center", va="bottom", fontsize=5.3, fontweight="bold", color=C["unified"])

    # ---------------------------------------------------------------
    # 3 — Identical bracketed 8×32 types.  Dots, not cell tables.
    # ---------------------------------------------------------------
    mx, mw, mh = 85.7, 21.6, 6.2
    # Minimal bit-value legend.
    ax.plot(87.6, 68.0, marker="s", markersize=2.4, markerfacecolor=C["bit1"], markeredgecolor=C["bit1"], zorder=20)
    ax.text(88.35, 68.0, "1", ha="left", va="center", fontsize=5.9, color=C["ink"])
    ax.plot(90.2, 68.0, marker="o", markersize=2.3, markerfacecolor=C["white"], markeredgecolor=C["bit0"], markeredgewidth=0.65, zorder=20)
    ax.text(90.95, 68.0, "0", ha="left", va="center", fontsize=5.9, color=C["ink"])

    draw_bit_matrix(ax, mx, 57.0, mw, mh, h_a, label=r"$\mathbf{X}_A^{(H)}$", label_position="above")
    draw_bit_matrix(ax, mx, 44.6, mw, mh, h_b, label=r"$\mathbf{X}_B^{(H)}$", label_position="above")
    draw_bit_matrix(
        ax,
        mx,
        27.5,
        mw,
        mh,
        e_a,
        label=r"$\mathbf{X}_A^{(E)}$",
        label_position="above",
        copy_highlights=a3_cells,
        copy_highlight_color=C["unified"],
    )
    ax.text(110.5, 34.45, r"16 copies of $a_3$", ha="right", va="center", fontsize=5.5, color=C["unified"])
    draw_bit_matrix(
        ax,
        mx,
        15.1,
        mw,
        mh,
        e_b,
        label=r"$\mathbf{X}_B^{(E)}$",
        label_position="above",
    )

    # ---------------------------------------------------------------
    # 4 — One shared pointwise operator, shown as two mutually exclusive modes.
    # ---------------------------------------------------------------
    op_x = 113.5
    ax.plot([op_x, op_x], [24.4, 53.9], color=C["and"], lw=0.82, zorder=4)
    ax.add_patch(Circle((op_x, 38.45), 0.92, facecolor=C["white"], edgecolor=C["and"], linewidth=0.82, zorder=15))
    ax.text(op_x, 38.45, r"$\odot$", ha="center", va="center", fontsize=7.8, fontweight="bold", color=C["and"], zorder=16)

    for y_top, y_bottom, y_mid, qy, qbits, qlabel in [
        (60.1, 47.7, 53.9, 50.8, h_q, r"$\mathbf{Q}^{(H)}$"),
        (30.6, 18.2, 24.4, 21.3, e_q, r"$\mathbf{Q}^{(E)}$"),
    ]:
        ax.plot([107.5, op_x], [y_top, y_mid], color=C["ink"], lw=0.58)
        ax.plot([107.5, op_x], [y_bottom, y_mid], color=C["ink"], lw=0.58)
        ax.add_patch(Circle((op_x, y_mid), 0.26, facecolor=C["and"], edgecolor=C["and"], linewidth=0.4, zorder=15))
        arrow(ax, op_x + 0.38, y_mid, 116.7, y_mid, color=C["and"], lw=0.78, ms=6.2)
        draw_bit_matrix(
            ax,
            117.0,
            qy,
            mw,
            mh,
            qbits,
            label=qlabel,
            label_position="above",
        )

    # One notation family covers both modes and all three same-shaped matrices.
    ax.text(
        70.0,
        4.1,
        r"$\tau\in\{H,E\}:\quad "
        r"\mathbf{X}_A^{(\tau)},\mathbf{X}_B^{(\tau)},\mathbf{Q}^{(\tau)}\in\{0,1\}^{8\times32},\qquad "
        r"\mathbf{Q}^{(\tau)}=\mathbf{X}_A^{(\tau)}\odot\mathbf{X}_B^{(\tau)}$",
        ha="center",
        va="center",
        fontsize=6.35,
        fontweight="bold",
        color=C["ink"],
    )

    return fig


def main():
    fig = build_figure()
    fig.savefig(OUT_STEM.with_suffix(".svg"), bbox_inches="tight", pad_inches=0.018, facecolor=C["white"])
    fig.savefig(OUT_STEM.with_suffix(".pdf"), bbox_inches="tight", pad_inches=0.018, facecolor=C["white"])
    tiff_rgba = OUT_STEM.with_name(OUT_STEM.name + "_rgba").with_suffix(".tiff")
    fig.savefig(
        tiff_rgba,
        dpi=600,
        bbox_inches="tight",
        pad_inches=0.018,
        facecolor=C["white"],
        pil_kwargs={"compression": "tiff_lzw"},
    )
    with Image.open(tiff_rgba) as image:
        image.convert("RGB").save(OUT_STEM.with_suffix(".tiff"), dpi=(600, 600), compression="tiff_lzw")
    tiff_rgba.unlink()
    fig.savefig(OUT_STEM.with_name(OUT_STEM.name + "_300dpi").with_suffix(".png"), dpi=300, bbox_inches="tight", pad_inches=0.018, facecolor=C["white"])
    fig.savefig(OUT_STEM.with_name(OUT_STEM.name + "_review_150dpi").with_suffix(".png"), dpi=150, bbox_inches="tight", pad_inches=0.018, facecolor=C["white"])
    plt.close(fig)


if __name__ == "__main__":
    main()
