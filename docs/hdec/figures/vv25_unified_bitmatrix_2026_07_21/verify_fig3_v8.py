from __future__ import annotations

import importlib.util
import random
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

from PIL import Image
from pypdf import PdfReader


HERE = Path(__file__).resolve().parent
FIGURE_SCRIPT = HERE / "build_fig3_unified_bitmatrix_python_v8.py"
REFERENCE_MODEL = (
    HERE.parents[3]
    / "scripts"
    / "hdec"
    / "vv25_byte_equation_model.py"
)
STEM = HERE / "HDEC_Fig3_unified_bitmatrix_python_v8"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def flattened(matrix):
    return [int(value) for row in matrix for value in row]


def check_layout(figmod, refmod):
    assert figmod.VV25_LAYOUT == refmod.LAYOUT
    assert len(figmod.VV25_LAYOUT) == 256
    assert len(set(figmod.VV25_LAYOUT)) == 256

    pairs = []
    for diag, term in figmod.VV25_LAYOUT:
        start_i = max(0, diag - 15)
        i = start_i + term
        j = diag - i
        assert 0 <= i < 16 and 0 <= j < 16
        pairs.append((i, j))
    assert len(set(pairs)) == 256
    assert Counter(i for i, _ in pairs) == Counter({i: 16 for i in range(16)})
    assert Counter(j for _, j in pairs) == Counter({j: 16 for j in range(16)})

    # The packed X_A matrix still contains all 16 natural copies of every a_i;
    # fixed packing changes position only.  In VV25 each row owns two copies.
    for i in range(16):
        coords = figmod.grid_coords_for_a_index(i)
        assert len(coords) == 16 and len(set(coords)) == 16
        assert Counter(r for r, _ in coords) == Counter({r: 2 for r in range(8)})
    assert figmod.grid_coords_for_a_index(3) == [
        (0, 3),
        (0, 18),
        (1, 3),
        (1, 17),
        (2, 3),
        (2, 16),
        (3, 3),
        (3, 11),
        (4, 3),
        (4, 11),
        (5, 3),
        (5, 11),
        (6, 3),
        (6, 11),
        (7, 3),
        (7, 19),
    ]


def check_bit_exactness(figmod, refmod):
    # Exhaustive one-hot coverage proves that every (a_i, b_j) pair is produced
    # exactly once and that the two operand matrices meet at the same flat slot.
    for i in range(16):
        for j in range(16):
            a_matrix, b_matrix = figmod.ecc_operand_bits(1 << i, 1 << j)
            product = flattened(figmod.and_bits(a_matrix, b_matrix))
            assert sum(product) == 1
            expected = refmod.matrix_product(1 << i, 1 << j)
            assert product == expected

    rng = random.Random(0x25A3)
    for _ in range(10_000):
        a = rng.randrange(1 << 16)
        b = rng.randrange(1 << 16)
        a_matrix, b_matrix = figmod.ecc_operand_bits(a, b)
        product = flattened(figmod.and_bits(a_matrix, b_matrix))
        assert product == refmod.matrix_product(a, b)


def check_artifacts():
    required = [
        STEM.with_suffix(".svg"),
        STEM.with_suffix(".pdf"),
        STEM.with_suffix(".tiff"),
        STEM.with_name(STEM.name + "_300dpi").with_suffix(".png"),
        STEM.with_name(STEM.name + "_review_150dpi").with_suffix(".png"),
    ]
    for path in required:
        assert path.is_file() and path.stat().st_size > 0

    root = ET.parse(STEM.with_suffix(".svg")).getroot()
    svg_ns = {"svg": "http://www.w3.org/2000/svg"}
    text_nodes = root.findall(".//svg:text", svg_ns)
    image_nodes = root.findall(".//svg:image", svg_ns)
    assert len(text_nodes) >= 40
    assert len(image_nodes) == 0

    reader = PdfReader(str(STEM.with_suffix(".pdf")))
    assert len(reader.pages) == 1
    resources = reader.pages[0].get("/Resources", {})
    xobjects = resources.get("/XObject", {}) if resources else {}
    raster_xobjects = 0
    if xobjects:
        for obj in xobjects.get_object().values():
            if obj.get_object().get("/Subtype") == "/Image":
                raster_xobjects += 1
    assert raster_xobjects == 0

    with Image.open(STEM.with_suffix(".tiff")) as image:
        assert image.mode == "RGB"
        assert image.info.get("compression") == "tiff_lzw"
        dpi = image.info.get("dpi", (0, 0))
        assert abs(dpi[0] - 600) < 1 and abs(dpi[1] - 600) < 1
        assert image.width >= 4000 and image.height >= 2000

    png_path = STEM.with_name(STEM.name + "_300dpi").with_suffix(".png")
    gray_path = STEM.with_name(STEM.name + "_grayscale_300dpi").with_suffix(".png")
    with Image.open(png_path) as image:
        image.convert("L").save(gray_path, dpi=(300, 300))

    return len(text_nodes), raster_xobjects


def check_text_inside_canvas(figmod):
    fig = figmod.build_figure()
    fig.canvas.draw()
    renderer = fig.canvas.get_renderer()
    canvas = fig.bbox
    outside = []
    texts = [
        artist
        for artist in fig.findobj(match=lambda obj: obj.__class__.__name__ == "Text")
        if artist.get_visible() and artist.get_text()
    ]
    for artist in texts:
        bbox = artist.get_window_extent(renderer=renderer)
        if bbox.x0 < canvas.x0 - 1 or bbox.y0 < canvas.y0 - 1 or bbox.x1 > canvas.x1 + 1 or bbox.y1 > canvas.y1 + 1:
            outside.append(artist.get_text())
    collisions = []
    for index, first in enumerate(texts):
        first_bbox = first.get_window_extent(renderer=renderer)
        for second in texts[index + 1 :]:
            second_bbox = second.get_window_extent(renderer=renderer)
            overlap_x = max(0, min(first_bbox.x1, second_bbox.x1) - max(first_bbox.x0, second_bbox.x0))
            overlap_y = max(0, min(first_bbox.y1, second_bbox.y1) - max(first_bbox.y0, second_bbox.y0))
            if overlap_x * overlap_y > 0.5:
                collisions.append((first.get_text(), second.get_text()))
    figmod.plt.close(fig)
    assert not outside, f"text outside canvas: {outside}"
    assert not collisions, f"text collisions: {collisions}"
    return len(outside), len(collisions)


def main():
    figmod = load_module("fig3_v8", FIGURE_SCRIPT)
    refmod = load_module("vv25_reference", REFERENCE_MODEL)
    check_layout(figmod, refmod)
    check_bit_exactness(figmod, refmod)
    text_nodes, raster_xobjects = check_artifacts()
    outside_count, collision_count = check_text_inside_canvas(figmod)
    print(
        "[FIG3_V8_QA] PASS "
        "layout=8x32 unique_pairs=256 copies_per_operand_bit=16 "
        "onehot=256 random16=10000 "
        f"svg_live_text={text_nodes} svg_images=0 pdf_raster_xobjects={raster_xobjects} "
        f"tiff=RGB@600dpi text_outside={outside_count} text_collisions={collision_count}"
    )


if __name__ == "__main__":
    main()
