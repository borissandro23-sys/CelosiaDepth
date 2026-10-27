# CelosiaDepth

Jailbreak tweak that adds a **lock-screen depth-style overlay** on **iOS 15** (rootless / **Dopamine**), aimed at Celosia-like wallpapers and similar still images.

> **Status:** scaffold for iPhone 6s · iOS 15.8.x · A9. Private SpringBoard selectors and wallpaper paths **must be verified on device** before relying on them in production.

## Features

- Detects lock-screen still wallpaper changes (cpbitmap / thumbnail fingerprints)
- Builds a **foreground layer** via:
  - optional **bundled masks** (`Resources/Masks/`) for known Celosia variants
  - conservative **luminance / edge heuristic** when no mask matches
- Places an overlay view in the lock UI hierarchy (best-effort on iOS 15 CoverSheet)
- Caches processed results (memory + disk under `/var/jb/.../Caches`)
- Rootless package (`iphoneos-arm64`), filter limited to SpringBoard
- Preferences: enable, intensity, prefer masks, debug logging

## Non-goals / limits

- Not a full port of iOS 16+ system Depth Effect / Portrait wallpaper pipeline
- Abstract wallpapers without a clear subject are **rejected** (no random blobs over the clock)
- No continuous Core ML in SpringBoard (A9 / 2 GB RAM)
- Class names such as `SBLockScreenManager`, `CSCoverSheetViewController`, `SBWallpaperController`, `SBFLockScreenDateView` are **common on iOS 14–15** but must be confirmed on **15.8.8**

## Requirements

| Item | Value |
|------|--------|
| Device | iPhone 6s (A9, arm64) |
| iOS | 15.0 – 15.8.x |
| Jailbreak | Dopamine (rootless) |
| Package manager | Sileo |
| Toolchain | Theos, `THEOS_PACKAGE_SCHEME=rootless` |

## Build

```bash
export THEOS=~/theos
export THEOS_PACKAGE_SCHEME=rootless
cd CelosiaDepth
make package FINALPACKAGE=1
```

Install the `.deb` from `packages/` via Sileo / `dpkg`.

Respring after install. Toggle settings by writing:

`/var/jb/var/mobile/Library/Preferences/com.celosiadepth.tweak.plist`

and posting Darwin notification `com.celosiadepth.tweak/ReloadPrefs` (or respring).

## Project layout

```
CelosiaDepth/
├── Makefile
├── control
├── Tweak.x
├── CelosiaDepth.plist
├── Sources/           # detector, processor, overlay, cache, prefs
├── Resources/         # Root.plist (+ Masks/*.png when available)
├── .github/workflows/build.yml
└── README.md
```

## Adding Celosia masks

1. Export a **grayscale / alpha mask** aligned to the wallpaper canvas (white = foreground).
2. Place as `Resources/Masks/<id>.png`.
3. Wire `<id>` in `CDWallpaperDetector` (`guessCelosiaMaskNameForImage:`) using perceptual hash or asset id once you have reference images.

Until masks exist, only the heuristic path runs — and it will often return `nil` for abstract art (by design).

## Safety

- Soft-fail if private classes/selectors are missing
- Overlay tag avoids duplicates after lock/unlock/respring
- Can disable via `Enabled = 0` in preferences
- Do **not** install untested builds as the only lock-screen modification on a daily driver without SSH / safe mode plan

## License

MIT (or project choice). Wallpaper artwork remains Apple / rights-holder property; ship only masks you have rights to distribute.

## Roadmap

- [ ] Device class-dump of SpringBoard on 15.8.8 → harden hooks
- [ ] Robust cpbitmap decoder for all 15.x variants
- [ ] Perceptual hash table for official Celosia stills
- [ ] Optional simple preferences bundle package
- [ ] CI with cached Theos + SDK 15
