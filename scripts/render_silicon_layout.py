#!/usr/bin/env python3

import argparse
from pathlib import Path

import klayout.db as db
import klayout.lay as lay


LAYER_COLORS = {
    (21, 0): 0x4F6BED,
    (22, 0): 0x8B5CF6,
    (30, 0): 0xFF4D6D,
    (31, 0): 0xFF8A4C,
    (32, 0): 0x2EC4B6,
    (33, 0): 0xF7DC6F,
    (34, 0): 0x4DA3FF,
    (35, 0): 0xEAF2FF,
    (36, 0): 0xFFB000,
    (38, 0): 0xFFF1C1,
    (40, 0): 0xE7FFF4,
    (42, 0): 0x48D597,
    (46, 0): 0xE855FF,
    (55, 0): 0xFFFFFF,
    (112, 1): 0x808080,
    (204, 0): 0xBFC7D5,
    (900, 0): 0x48D597,
    (901, 0): 0x4DA3FF,
    (902, 0): 0xFFD166,
    (903, 0): 0xB47CFF,
    (904, 0): 0xFF4D6D,
}

FEOL_LAYERS = {
    (21, 0),
    (22, 0),
    (30, 0),
    (31, 0),
    (32, 0),
    (33, 0),
    (34, 0),
}
ROUTING_LAYERS = {
    (34, 0),
    (35, 0),
    (36, 0),
    (38, 0),
    (40, 0),
    (42, 0),
    (46, 0),
}
TOP_METAL_LAYERS = {(40, 0), (42, 0), (46, 0)}
PLACEMENT_LAYERS = {
    (900, 0),
    (901, 0),
    (902, 0),
    (903, 0),
    (904, 0),
}


def configure_layers(
    view: lay.LayoutView, visible_layers: set[tuple[int, int]] | None
) -> None:
    view.add_missing_layers()
    for layer in view.each_layer():
        key = (layer.source_layer, layer.source_datatype)
        layer.visible = visible_layers is None or key in visible_layers
        if key in LAYER_COLORS:
            layer.fill_color = LAYER_COLORS[key]
            layer.frame_color = LAYER_COLORS[key]
        layer.transparent = key in ROUTING_LAYERS
        layer.width = 1


def render(
    gds: Path,
    output: Path,
    visible_layers: set[tuple[int, int]] | None,
    target_box: db.DBox | None = None,
) -> None:
    view = lay.LayoutView()
    view.set_config("background-color", "#10131a")
    view.set_config("grid-visible", "false")
    view.set_config("text-visible", "false")
    view.load_layout(str(gds))
    view.max_hier()
    configure_layers(view, visible_layers)
    view.zoom_fit()
    view.save_image_with_options(
        str(output),
        2400,
        1300,
        0,
        2,
        0,
        target_box or db.DBox(),
        False,
    )


def placement_layer(cell_name: str) -> tuple[int, int] | None:
    name = cell_name.lower()
    if "fill" in name or "endcap" in name:
        return None
    if "ant" in name and "diode" in name:
        return (904, 0)
    if "clk" in name or "dly" in name:
        return (902, 0)
    if "dff" in name or "latch" in name:
        return (901, 0)
    if "__buf" in name or "__inv" in name:
        return (903, 0)
    return (900, 0)


def create_placement_gds(source_gds: Path, output_gds: Path) -> None:
    source = db.Layout()
    source.read(str(source_gds))
    source_top = source.top_cell()

    placement = db.Layout()
    placement.dbu = source.dbu
    top = placement.create_cell("placement_map")
    for instance in source_top.each_inst():
        layer_key = placement_layer(instance.cell.name)
        if layer_key is not None:
            top.shapes(placement.layer(*layer_key)).insert(instance.bbox())

    placement.write(str(output_gds))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Render GF180 signoff GDS inspection images with KLayout"
    )
    parser.add_argument("gds", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    renders = [
        ("01-full-composite.png", None, None),
        ("02-cell-feol.png", FEOL_LAYERS, None),
        ("03-metal-routing.png", ROUTING_LAYERS, None),
        ("04-top-metal-power.png", TOP_METAL_LAYERS, None),
        (
            "05-center-detail.png",
            None,
            db.DBox(500.0, 200.0, 940.0, 540.0),
        ),
    ]
    for filename, layers, target_box in renders:
        path = args.output_dir / filename
        render(args.gds, path, layers, target_box)
        print(path)

    placement_gds = args.output_dir / ".cell-placement.gds"
    create_placement_gds(args.gds, placement_gds)
    placement_image = args.output_dir / "06-cell-placement.png"
    render(placement_gds, placement_image, PLACEMENT_LAYERS)
    placement_gds.unlink()
    print(placement_image)


if __name__ == "__main__":
    main()
