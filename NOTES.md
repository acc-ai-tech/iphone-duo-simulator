# Design notes

Verified with Xcode 27.0, Swift 6.4 and the iOS 27.0 simulator on an **iPad Pro 13-inch (M5)** (1032×1376 pt).

## Status

| Area | Verified by |
|---|---|
| Core model, presets, host controller | 33 unit tests; UIKit example checked in every preset |
| Traits and SwiftUI environment | SwiftUI example: environment values, size classes, `NavigationSplitView` collapsing |
| Animations | Frame-by-frame screenshots of the 3D fold, using slowed-down presets |
| Debug panel and keyboard | Panel checked visually. Key commands are registered, but key presses weren't automated |
| Half-open posture | 3D view in portrait and landscape, `hingeRect` in UIKit and SwiftUI |
| Tools | Screenshots and stress test covered by unit tests; terminal commands and the report tested in the simulator |
| Release builds | A Release build launched in the simulator: full-size app, no panel, no logs, terminal commands ignored |

The package and both examples build without warnings.

## Design decisions

**All geometry comes from JSON.** Screen sizes, angles, thresholds, animation timings and tool settings live in
`DuoPresets.json`. Colors and paddings of the panel and device frame are visual constants, not part of the model.

**Split presets reference a physical screen.** `inner.split.half` and `inner.split.stacked` point at their parent screen
(`"screen": "inner.landscape"`). The device frame covers the whole inner screen and the unused half shows a faint
placeholder. The hinge sits exactly on the content edge, so `hingeRect` is `.null`: a hinge belongs to the content only
when its center line is strictly inside it.

**Switching presets keeps the half-open angle.** Choosing an inner preset while the inner screen is active keeps the
current angle, so you can rotate a half-open device. From the outer screen, inner presets open to `angles.open`.

**State tokens.** Screenshot and stress test sequences use `presetId[@angle]`, for example `inner.portrait@90`.

**`DuoPreview.state` is the target state.** It is committed when a transition starts, so observers and the panel see the
destination immediately. Angle changes without animation (the slider, `setHingeAngle(_:animated: false)`) update traits
on every change.

**Requests queue up.** A request made during a transition waits for it to finish. The latest request wins, and every
completion handler still runs.

**The async API is `transition(to:animation:)`.** An async overload of `set(_:animation:)` would make calls without
`await` ambiguous inside async contexts.

**A custom transition coordinator.** `DuoTransitionCoordinator` implements `UIViewControllerTransitionCoordinator`.
Alongside blocks run inside the emulator's own animation, and completions run when it ends. The host deliberately
doesn't call `super.viewWillTransition` when the iPad rotates, because the content size doesn't depend on the window.

**Fold leaves are image snapshots.** The device body (frame, screen and hinge line) is rendered with
`drawHierarchy(in:afterScreenUpdates:)` and split into halves with `CALayer.contentsRect`, instead of using
`resizableSnapshotView`. The same code drives both the fold animation and the timer-refreshed 3D view.

**Fold geometry.** Each inner leaf rotates by `(180 − angle) / 2`, forming a V toward the viewer. On the outer screen a
single leaf rotates by `angle / displaySwitchAngle × rotation(displaySwitchAngle)`, so both rotations match at the switch
angle and the hand-off looks continuous.

**Orientation and split changes don't fold.** When a 3D fold doesn't cross the display switch angle but the layout
changes, it falls back to a regular animated UIKit transition.

**Blur during 3D fold.** Blurred copies of the snapshots (`CIGaussianBlur`) cross-fade over the leaves. At the end, a
blurred snapshot of the new layout dissolves into the live content. Tuned with `blurRadius`, `blurRampFraction` and
`blurFadeOut`.

**On by default in Debug.** The emulator no longer needs a launch argument. `-DuoPreviewOff` or `DUO_PREVIEW=0` turns
it off. Release builds are always off.

**Small windows scale the device.** In Stage Manager or with a landscape iPad, the device is scaled down with a transform
(no less than 50%) instead of refusing to install. Content keeps its exact point size and traits. The docked panel
reserves space at the top and the device is centered below it.

**Panel height follows its content.** The panel is a SwiftUI view in a `UIHostingController` that reports size changes
through `preferredContentSize`. Measuring with `sizeThatFits` right after a state change returned the previous height.

**Terminal commands for options.** `com.duolab.option.<name>.on|off` exists because options can't be changed from outside
through `UserDefaults`: `cfprefsd` caches the values, so editing the plist on disk has no effect.

**Lifecycle tracking without swizzling.** `DuoPreview.track(self)` counts loads, and deallocation is detected with an
associated object.

**Side toolbar.** For presets with `"sideToolbar": true` in a flat posture (outer, or fully open), the host scans for
visible `UINavigationController`s every 0.3 s, hides their navigation bar and toolbar, and shows their buttons as icons in
a `UIGlassEffect` capsule (a blur material before iOS 26). `additionalSafeAreaInsets.right` grows by `sideToolbarWidth`.
Buttons are triggered with `UIAction.performWithSender`, `UIApplication.sendAction`, menus or `UIControl.sendActions`.
Back pops the stack, split views get a sidebar toggle, and search temporarily brings the navigation bar back. Bars are
restored when the state changes. Known gaps:

- A system bar item without an action can't be told apart from a spacer, so it's skipped. In the UIKit example the feed's
  `+` button disappears for this reason.
- System items with an action expose no image, so they get a letter or question mark icon.
- Apps that toggle their own navigation bar will conflict with the hiding.

**Hinge-aligned columns are an app decision.** Both examples size their sidebar to `hingeRect.minX` when half-open with a
vertical hinge, giving a 50/50 split. The emulator only provides the hinge; it doesn't move app columns.

**Modals.** UIKit has no public hook for placing presentations, so the host moves the container view UIKit creates in the
window (the sibling of the host's own container) into the content area, or into the half past the hinge while half-open,
where it also applies the leaf rotation if the 3D view is on. A display link keeps the frame in sync; the host reference
is weak because the link retains its target. Popovers with a source view and the keyboard stay where UIKit puts them.

## Research

### Hosting modes

The default is now `.resizeWindow`: the app keeps its window and its hierarchy, the window is resized to the content
frame (with a transform when the device is scaled), the device chrome is drawn in a window one level below, and the fold
leaves, the 3D badge, the hinge line and the right toolbar are drawn above it (the hinge line and toolbar as subviews of
the app window, the leaves in a passthrough window above). Snapshots for the fold compose the chrome image with a
`drawHierarchy` image of the app window; the app window is never hidden, because a hidden window renders nothing.

`.containerChild` keeps the old behaviour and is used as a fallback when the window has no scene (unit tests).

Why: moving a SwiftUI root controller makes SwiftUI rebuild the hierarchy and reset scene-level `@State`. A real app
(a splash flag in `App` plus `onAppear`) never left its splash screen. Resizing the window fixes that class of problems
and also removes the appearance-transition warnings.

### Moving the SwiftUI root into a child controller

**Works, and it's the default.** The `UIHostingController` created by `WindowGroup` becomes a child of the host. Verified
in the SwiftUI example with `NavigationSplitView`, `.searchable`, `.sheet`, `@State` and trait-bridged environment values
(`UITraitBridgedEnvironmentKey`). `horizontalSizeClass` updates on fold and unfold, and view state survives.

Installing after a single `DispatchQueue.main.async` produced "Unbalanced calls to begin/end appearance transitions" for
the hosting controller. Waiting one more run loop turn, until the root finishes appearing, fixes it. The first frame
still renders at iPad size. UIKit apps hit the same warning when installing after `makeKeyAndVisible()`, which is why the
docs recommend installing before it.

A fallback, `DuoPreviewHostView { content }`, sizes the content and injects size classes, safe area and Duo environment
values without touching the window. It has no device frame, panel or `viewWillTransition`, and exists in case moving the
root breaks in a future SwiftUI release.

**Hinge coordinates in SwiftUI.** `.global` inside a `UIHostingController` doesn't match the content's coordinate space.
Declare a named coordinate space on the root view and convert through it, as the examples do.

### Live content on two rotated leaves

**Not possible with public API, so the 3D view uses snapshots.**

- A layer renders exactly once in the tree. The only public way to show it twice with different transforms is
  `CAReplicatorLayer`.
- `CAReplicatorLayer` applies a cumulative `instanceTransform` (instance 0 is never transformed) and a single mask for all
  instances, so each copy can't be masked to one half. Nesting replicators would require the live view to have two
  parents.
- `_UIPortalView` and `CAPortalLayer` would solve it, but they're private.

The 3D view therefore refreshes `drawHierarchy(afterScreenUpdates: false)` snapshots at `halfOpen3DFPS` (15 fps) and
disables interaction while it's shown. This conclusion comes from analysis; no replicator prototype was built.

## Bugs found during development

- **Image diff always reported zero changes.** A shared `CIContext` returned stale, all-zero results when comparing
  renderer-produced images one after another (`a` vs `a`, then `a` vs `b`). A standalone macOS script and an isolated test
  both counted correctly. Fixed by creating a `CIContext` with `.cacheIntermediates: false` per comparison and counting
  pixels through an RGBA8 `CGContext` with a known row order.
- The panel initially appeared on the left, over the device, because its position was computed before layout.
- The "3D preview only" badge was hidden behind the fold overlay.

## Known limitations

**Modal presentations**, checked with screenshots in the UIKit example (`-screen modals -present <style>`):

- `.currentContext` and `.overCurrentContext` with `definesPresentationContext = true` stay inside the emulated screen.
- `.formSheet` and `.pageSheet` are centered on the iPad window and extend past the emulated screen. They ignore
  `definesPresentationContext`, and redirecting them would require swizzling.
- Alerts are centered on the iPad window. With a centered device they look right, but they aren't tied to it.
- Sheets with detents are placed by UIKit relative to the window, with no guarantees.
- Modal content gets its size and size classes from the iPad window, not from the preset.
- Presentation placement isn't unit-tested: `present` never completes for a scene-less `UIWindow` in xctest.

**Other limitations**

- The keyboard spans the whole iPad, and `keyboardLayoutGuide` measures against it. A device-sized keyboard can't be
  emulated with public API.
- Action sheets, popovers, activity views and system sheets are also positioned against the iPad window.
- The status bar and home indicator belong to the iPad. Emulated safe areas come from `safeAreaInsets` in the JSON.
- Darwin notifications sent in the first half second or so after launch, before the host is installed, are lost.
- During a 3D fold the content is covered by the overlay, and `DuoPreview.state` already reports the destination.

**Live resize.** A mode that resized live content every frame (`DuoAnimation.continuous`) existed and was removed on
request; only the 3D fold and the instant switch are left. Its measured performance (10–50 fps in a Debug build) no
longer applies.

## Open questions

- Real point sizes, scale and safe areas. Current values are derived from 2034×1398 and 2670×1878 px at @3x.
- The display switch angle (40°) and posture thresholds (10° and 160°).
- Which size classes Apple assigns to each state, especially split layouts and inner portrait.
- The hinge position. A book-style fold is assumed, with a vertical hinge on the landscape inner screen.
- Whether Apple ships a posture or hinge API. If it does, `DuoPostureTrait` and `DuoHingeTrait` can switch their data
  source without changes to app code.
