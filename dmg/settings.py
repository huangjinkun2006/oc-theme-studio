# dmgbuild settings: standard "drag the app onto Applications" installer.
# The layout is written straight into .DS_Store, so Finder's AppleEvents
# permission is NOT required (it is denied in some sandboxed sessions).

import os

# dmgbuild exec()s this file, so __file__ is unavailable; it does expose the
# output image path as `filename`. The build script also passes OCTHEME_ROOT.
ROOT = os.environ.get("OCTHEME_ROOT") or os.path.dirname(os.path.abspath(filename))
HERE = os.path.join(ROOT, "SwiftApp", "dmg")
STAGE = os.path.join(ROOT, ".cache", "dmg", "stage")

volume_name = "OC Theme Studio"
format = "UDZO"               # compressed, read-only disk image
filesystem = "HFS+"
compression_level = 9

files = [
    os.path.join(STAGE, "OC Theme Studio.app"),
]
symlinks = {
    "Applications": "/Applications",
}

background = os.path.join(HERE, "background.png")

# Window matches the 700x420 artwork. Positions are icon centres measured
# from the top-left of the icon view; the arrow occupies the gap between them.
window_rect = ((100, 100), (700, 420))
default_view = "icon-view"
icon_size = 128.0
text_size = 13.0
label_pos = "bottom"
icon_locations = {
    "OC Theme Studio.app": (170, 190),
    "Applications": (530, 190),
}

show_status_bar = False
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_tab_view = False
show_icon_preview = False
