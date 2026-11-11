# Forever Transmog Finder: logo

Last updated: 2026-11-11.

## Concept

A knight bust sits inside a faceted gold hexagon gem. The bust is split down the middle:

- **Left half: missing.** A near-black silhouette with a faint violet rim, like an appearance you have not collected yet.
- **Right half: collected.** The same shape lit in arcane teal fading to lavender, with a soft teal glow.

A thin white seam glows where the two halves meet, as if the look is being revealed. One cream sparkle sits beside the helmet. The gem sits on a dark rounded-square badge with a faint violet aura, matching the addon's dark flat panels and gold accent.

At 64 px and 32 px the design still reads as a gold hexagon with a half-dark, half-lit figure. The logo has no text, so nothing becomes illegible at thumbnail size.

## Files

| File | What it is |
|---|---|
| `logo.svg` | The vector source for the avatar (400x400 viewBox, hand-written, no fonts or embedded images) |
| `logo-400.png` | The CurseForge project avatar, 400x400 RGBA with transparent corners |
| `logo-1024.png` | The same design at 1024x1024, for a GitHub social preview or a banner |
| `icon.svg` | The vector source for the in-game icon: a simplified, full-bleed version without the bezel or sparkle, with the bust enlarged |
| `icon-64.tga` | The in-game icon: 64x64, 32-bit uncompressed TGA (type 2, 8 alpha bits, bottom-left origin, fully opaque) |
| `preview-sheet.png` | The avatar at 400, 128, 64 and 32 px, then the in-game icon at 64 px, on white and on #1F1F1F |

## Colours

| Role | Hex |
|---|---|
| Gold accent (right bezel facet) | `#E6B422` |
| Other gold bezel facets, light to dark | `#FFE79A` `#F7D56A` `#EDC24A` `#C08F1C` `#A97A12` |
| Facet lines | `#0E0F14` |
| Badge field (radial gradient) | `#231D36` to `#121318` |
| Badge rim | `#363C4A` |
| Aura behind the gem | `#7C4DFF` at 30 % opacity, fading out |
| Gem interior (radial gradient) | `#4A3596` to `#30226A` to `#1A1438` |
| Collected half (vertical gradient) | `#A6FFF4` to `#3EDCD8` to `#B9A2FF` |
| Collected glow | `#4FE6DA` |
| Seam | `#FFFFFF` core, `#7FF5EA` glow |
| Missing half | `#0C0C14` fill, `#5A45B0` rim (`#6A55C8` on the in-game icon) |
| Sparkle | `#FFF3C4` |

## How it was made

1. The SVGs were written by hand. They use only plain geometry: polygons, paths, gradients, a Gaussian-blur glow and clip paths. They contain no text, fonts, embedded images or external references.
2. The PNGs were rendered with headless Chrome at their final size, with a transparent background:
   `chrome --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 --window-size=400,400 --screenshot=logo-400.png file:///<folder>/logo.svg`
   For the 1024 version, the same command was run on a copy of the SVG with `width` and `height` set to 1024, and `--window-size` set to 1024,1024.
3. The icon was rendered from `icon.svg` at 512 px and then downscaled to 64 px with a Lanczos filter. It was saved as a TGA with Pillow.
4. Every PNG was re-encoded from raw pixels, so the files contain only the IHDR, IDAT and IEND chunks: no text chunks, EXIF, ICC profile or timestamps. The TGA has an empty image-ID field.

## Licence

This logo is original work, made for Forever Transmog Finder by the addon's author. It uses no Blizzard Entertainment art, icons, textures, fonts or logos, and it is not derived from any other addon's logo.

The logo is released under **GPL-3.0-or-later**, the same licence as the addon. If the author prefers, they can also offer it under **CC BY 4.0** for use outside the addon (for example on a website or in a video).

## Using the icon in the addon

- Copy `icon-64.tga` into the addon, for example as `ForeverTransmogFinder/Media/icon-64.tga`. The release tool's exclude list does not match `.tga`, so the file ships.
- TOC: `## IconTexture: Interface\AddOns\ForeverTransmogFinder\Media\icon-64`. You can omit the extension. The AddOns list and the addon compartment both use this icon.
- Minimap button: point the `ICON` constant in `Minimap.lua` at the same path. The existing circular mask and the 19 px size work with this art. The 0.08 texture-coordinate inset that is currently used to trim a Blizzard icon's border is no longer needed: `SetTexCoord(0, 1, 0, 1)` shows the whole field, but either setting reads well.
