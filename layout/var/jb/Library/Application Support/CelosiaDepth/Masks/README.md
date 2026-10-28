# Manual foreground masks

CelosiaDepth does not currently ship a mask for the iOS 27 Light wallpaper.

To enable a manually authored mask, place a PNG at:

`/var/jb/Library/Application Support/CelosiaDepth/Masks/ios27_light.png`

Mask canvas should match the wallpaper composition/aspect ratio:
- white (RGB 255,255,255) = foreground to draw above the clock;
- black (RGB 0,0,0) = transparent/background;
- gray = partial transparency/soft edge.

Use an opaque grayscale PNG for the clearest result. The code converts mask luminance into alpha; an ordinary opaque black-and-white image is supported.

IMPORTANT:
- The existence of `ios27_light.png` is an explicit opt-in, not automatic wallpaper recognition. Keep this file only while using the matching wallpaper.
- A mask must follow the actual shape of a foreground element. Do not paint the entire lower half white: that will cover the clock rather than create depth.
- Abstract gradients may have no suitable foreground element. In that case, leave the file absent and expect no depth overlay.
- The repository intentionally does not include a fabricated mask: a useful mask must be authored against the actual full-resolution wallpaper.
