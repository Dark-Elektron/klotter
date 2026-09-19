# Release smoke checklist

Run this against a **release build**, not the debug one:

```
flutter build appbundle --release
flutter install --release      # or install the APK on a device
```

## Why a release build specifically

Much of this app's geometry goes through `laidOutBox`, which decides whether a
box is usable. Part of that decision — `debugNeedsLayout` — is computed inside
an `assert`, so **in release it is never set** and the helper accepts boxes it
would refuse in debug. Anything positioned from a measured box can therefore
behave differently in the two builds: the walkthrough spotlight, the caret, tap
targeting, the long-press readout.

Debug-only assertions also mean a release build cannot show the layout errors
that debugging surfaces. A silent release is not evidence that the layout is
right — only that nothing is checking.

## Launch

- [ ] Cold start from the launcher: keypad visible on the first frame, no blank
      area where it should be.
- [ ] No error banner over the plot on a cell that has never been edited.
- [ ] Rows restored from the previous session, in order, with their colours and
      their eye state.
- [ ] The caret sits on the expression, not off to its left. Check on a cell
      that was **not** the last one edited.

## Walkthrough

Reset it from Settings → Show Tutorial.

- [ ] Every step highlights something. The step before a swipe is the one that
      has failed before.
- [ ] The tour opens on the scientific keys, so "swipe LEFT" has somewhere to
      go on the first attempt.
- [ ] Swipe left reaches the extras; swipe right returns.
- [ ] Skip works, and starting it again from Settings still works.
- [ ] On a tablet or in landscape: the three block highlights land on their own
      blocks, and no step asks for a swipe.

## Each plot kind

One cell at a time, then two together:

- [ ] `x^2+y` — surface, 3D and 2D.
- [ ] `x^2+y^2=1` — implicit. Home frames it rather than sitting at ±5.
- [ ] `x^2+y^2+z^2=1` — sphere. Home frames it, and it is **round**, not an egg.
- [ ] `y x̂ - x ŷ` — arrow field, with a colourbar.
- [ ] `u x̂ + u² ŷ` — parametric sweep.
- [ ] A complex function — Argand view, centred on the origin.
- [ ] Two surfaces at once with contours on: **both** get contour lines.
- [ ] Two fields at once: two sets of arrows, two colourbars.

## Rows

- [ ] ⌘ adds a row rather than a newline.
- [ ] Backspace on an empty row removes that row; on the last row it removes the
      cell.
- [ ] A new cell cannot be added while one is empty.
- [ ] The colour dot matches the curve, in 2D **and** 3D.
- [ ] The eye hides: a surface, an arrow field, a parametric sweep.
- [ ] Hiding a row raises **no** error banner, and hiding one of two leaves the
      other's colour unchanged.
- [ ] A genuinely mistyped line still reports an error.

## View controls

- [ ] Zoom, pan, home, set range — each responds on the first tap.
- [ ] Tapping zoom while zoom is already active opens Free / X / Y / Z.
- [ ] Long-press on a surface, a sweep and a complex surface gives a readout.
- [ ] A hidden curve cannot be long-pressed and does not affect the fit.

## Undo, redo, persistence

- [ ] Undo after an edit keeps **every** row of the cell, not just the one the
      caret was in.
- [ ] Redo restores them all.
- [ ] Background the app, open several others, return: state intact, no crash.
- [ ] Force-stop and reopen: rows, hidden flags and the view come back.

## Rotation and shape

- [ ] Rotate mid-session: the keypad survives, the plot keeps its view.
- [ ] Landscape on a phone, and a tablet in both orientations.
- [ ] Left-handed setting: menus, the colour dot and the eye all mirror.
- [ ] System font at 150%: nothing clipped, the keypad still fits.

## Export

- [ ] ⇪ saves an image and a PDF.
- [ ] A hidden curve is absent from the export.
- [ ] The exported plot is the plot, without the expression rows floating over
      it.

## Before uploading

- [ ] Settings has **no** DIAGNOSTICS section. It is off unless built with
      `--dart-define=SHOW_DIAGNOSTICS=true`.
- [ ] App icon and splash are the intended ones on a real device.
- [ ] Version and build number bumped in `pubspec.yaml`.
- [ ] Data safety form: the app stores expressions and a crash log in local
      preferences and sends nothing anywhere. Confirm that is still true before
      declaring it.
