# App icon

`AppIcon.svg` is the source for the app icon (1024×1024, macOS icon grid: an
824 px rounded square centred on the canvas). The PNGs in
`Sources/Assets.xcassets/AppIcon.appiconset/` are rendered from it.

To change the icon, edit the SVG, then re-render the PNGs: render it to a
1024 px PNG (any SVG renderer, or `node render-icon.js` with Playwright, run
from a folder containing the SVG renamed to `final.svg`), and resize to the
sizes listed in the appiconset's `Contents.json`.
