# MouseRift

MouseRift is a macOS menu bar utility for independent mouse scrolling and
middle-button swipe gestures.

## Features

- Reverse an external mouse wheel without changing trackpad scrolling.
- Distinguish smooth-scrolling mice from trackpads using multi-touch gesture
  events and the underlying IOHID scroll event.
- Use middle-button swipes for macOS actions:
  - Left: move the active window left (`Fn-Control-Left`)
  - Right: move the active window right (`Fn-Control-Right`)
  - Up: Mission Control
  - Down: Show Desktop (`Fn-F11`)
- Preserve an ordinary middle click when movement stays below the gesture
  threshold.
- Start at login and manage Accessibility/Input Monitoring permissions from
  the preferences window.

## Building

Clone with submodules:

```sh
git clone --recurse-submodules git@github.com:bramblex/MouseRift.git
cd MouseRift
git -c fetch.recurseSubmodules=false fetch \
  https://github.com/pilotmoon/Scroll-Reverser.git --tags
```

The upstream tags are used by the shared build scripts to generate the app
version. Open `MouseRift.xcodeproj` in Xcode and build the `MouseRift` scheme.
Select your own development team when producing a signed build; unsigned local
and CI builds use an ad-hoc signature for the embedded Sparkle framework.

The current project requires macOS 13.5 or later.

## Permissions

MouseRift requires both permissions below:

- System Settings → Privacy & Security → Accessibility
- System Settings → Privacy & Security → Input Monitoring

Restart MouseRift after granting them.

## Upstream and license

MouseRift is a derivative of
[Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser), copyright
2011 Nicholas Moore, licensed under Apache License 2.0.

The original `LICENSE` and `NOTICE` files are retained. Modified source files
continue to carry the upstream license header; repository history and this
README document the MouseRift changes. The Scroll Reverser name and icon are
not used as MouseRift product identity.
