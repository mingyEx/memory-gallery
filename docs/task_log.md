# Task Log

## 2026-05-10

### What Was Completed
- Changed fullscreen photo viewing to use a `cover`-style base display instead of the old `contain` default, so entering fullscreen now behaves more like a phone gallery viewer.
- Kept image ratios intact in fullscreen while allowing overflow cropping beyond the viewport edges.
- Reworked the regular Android photo-detail image region (`subwindow 7`) away from the previous fixed-height container toward a width-priority image block that grows vertically with the image.
- Switched the regular Android photo-detail image block to natural-width rendering using the available parent width instead of the older viewport-style fixed-height frame.
- Turned the debug-only red borders and top-right subwindow number tags back off for default packaged builds.
- Rebuilt the Android release APK and refreshed the packaged installer output in `build/installers`.

### Files Changed
- `lib/main.dart`
- `WORKLOG.md`
- `README.md`
- `docs/current_status.md`
- `docs/task_log.md`

### How To Verify
- Run `flutter analyze --no-pub`
- Run `flutter build apk`
- Open Android photo detail in normal mode and confirm the image in `subwindow 7` expands by width and the region height follows the image.
- Open fullscreen mode and confirm the initial display now behaves like `cover`: ratio preserved, at least one axis filled, overflow allowed to crop.
- Confirm the packaged UI no longer shows the old debug red frames or subwindow number tags.

### Current Problem
- The Android regular photo-detail image region still needs real-device visual confirmation; the latest change compiles and packages, but the user has not yet confirmed that `subwindow 7` now matches the intended article-style width-priority behavior.
- The local untracked file `相册界面2.png` still has not been added to version control.
- The generated `feature_check_report.html` is still local-only and not committed.

### Next Suggestion
- Validate the normal Android photo-detail image block and fullscreen default on device, then continue iterating only on `subwindow 7` if the width-priority behavior still needs tightening.

## 2026-05-08

### What Was Completed
- Added strict `createdAt / updatedAt` handling to album metadata so create, restore, move, and copy flows no longer rely on loose subtitle-only dates.
- Changed image import to uncompressed local copying and removed Android-side quality downscaling from the main image-pick flows.
- Removed the mobile single-album cover tilt so the focused cover no longer uses the old angled `rotateY` effect.
- Reworked Android photo detail so the note area can be treated as its own debug-numbered subwindow, separate from the image and title regions.
- Moved the photo date into the title subwindow, alongside the photo title instead of the note subwindow.
- Increased the Android note editor to a 10-line minimum, made it content-driven, and added a draggable right-side scrollbar for long text.
- Kept fullscreen mobile pinch/drag behavior on a separate Android-specific parameter set and rebuilt the Android release package after the interaction changes.
- Tightened Android detail layouts again so the stacked sections sit closer to full width, the title/date region is more compact, and note tools sit at the lower-right.
- Added a settings-panel `关于软件` action that reads `about.txt` from the repo root and shows it in a read-only dialog.
- Renamed the Android app to `予已拾光` and regenerated Android launcher icons from `pic.jpg`.
- Synced the current Windows-side UI refinements onto Android while preserving the intended mobile-only layout rules:
  - photo detail stays `上图下文`
  - album detail stays `上文下图`
- Reworked Android album detail so the top section is now text-first, with inline album title / description editing and a separate cover-edit entry.
- Removed the extra album-cover display block from Android album detail subwindow 5 after confirming it was the unwanted duplicated element.
- Reduced Android spine-wall widths to half of the shared desktop baseline so the mobile compact mode feels less heavy.
- Fixed dark-mode readability across shared surfaces, especially the `移动到其他相册 / 复制到其他相册` dialog and other deep-background cards that still used dark text.
- Applied theme-aware title/body/muted text helpers to shared UI areas so Windows and Android both inherit lighter text on dark surfaces.
- Rebuilt Windows and Android packages after the Android layout and dark-mode changes.

### Files Changed
- `lib/main.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/mipmap-*/ic_launcher.png`
- `about.txt`
- `pic.jpg`
- `test/widget_test.dart`
- `WORKLOG.md`
- `README.md`
- `docs/current_status.md`
- `docs/task_log.md`

### How To Verify
- Run `flutter analyze --no-pub`
- Run `flutter build apk`
- Open settings and confirm `关于软件` opens a read-only dialog showing `about.txt`.
- On Android, confirm the app name is `予已拾光` and the launcher icon has updated from `pic.jpg`.
- On Android, open photo detail and confirm the title/date live in subwindow `9` while note content lives in subwindow `10`.
- On Android, enter note edit mode and confirm the note editor starts at 10 lines, grows with content, and shows a draggable scrollbar on the right.
- On Android, open fullscreen photo mode and confirm pinch/drag uses the dedicated mobile interaction path.
- On Android, open album detail and confirm subwindow 5 no longer shows a duplicated cover block.
- On Android, switch to spine-wall mode and confirm the spines are visibly narrower than before.
- In dark mode on both Windows and Android, open the move/copy target dialog and confirm the dialog title and album names are readable on dark backgrounds.
- In dark mode, check add-photo, favorites, and recycle-bin text for remaining deep-background dark-text regressions.

### Current Problem
- The local untracked file `相册界面2.png` still has not been added to version control.
- The generated `feature_check_report.html` is still local-only and not committed.
- A few pages may still contain older hardcoded light-mode-first colors, so dark mode should get another focused cleanup pass.

### Next Suggestion
- Validate the latest Android photo-detail editing and fullscreen gesture behavior on device, then update or repair widget tests once the UI behavior is stable enough to lock.

## 2026-05-07

### What Was Completed
- Added album-detail multi-select actions for `删除`, `移动`, and `复制`.
- Matched the album-detail selection interaction to the recycle bin pattern: icon+text `批量选中`, red border selection highlight, and no auto-exit when selection count returns to zero.
- Reworked the target-album picker for move/copy into a compact square-corner dialog that only shows bordered album names and a trailing `新建列表` entry.
- Restored the focused album cover pencil in single-album mode and changed it to pick a replacement cover from the current album's own photo thumbnails.
- Split single-album editing into two separate paths:
  - cover editing from the cover area
  - inline text editing for album title and album description from the text side
- Hid the debug-only subwindow red frames and top-right number tags from the default UI.
- Removed the photo-detail save warning for empty note text so blank notes can now be saved.
- Added clearer light borders to fullscreen action buttons and enabled mouse-wheel zoom in both photo detail and fullscreen views.
- Updated `WORKLOG.md`, `README.md`, and `docs/current_status.md` so the documentation matches the new focused-album, fullscreen, and album-detail behavior.

### Files Changed
- `lib/main.dart`
- `test/widget_test.dart`
- `WORKLOG.md`
- `README.md`
- `docs/current_status.md`
- `docs/task_log.md`

### How To Verify
- Run `flutter analyze --no-pub`
- Run `flutter build windows`
- Open the focused album mode on Windows
- Click the cover pencil and confirm the dialog shows thumbnails from the current album
- Click the text-side pencil and confirm album title / description can be edited inline
- Open album detail, enter `批量选中`, deselect back to zero, and confirm selection mode remains active until manually cancelled
- Open photo detail and fullscreen mode, then use the mouse wheel to zoom
- Confirm the fullscreen action buttons show visible light borders on the dark background
- Confirm the old debug subwindow marks are no longer visible

### Current Problem
- The local untracked file `相册界面2.png` still has not been added to version control.
- `flutter test` currently fails in a few widget tests that still expect older photo-detail layout and older album-editor entry points.

### Next Suggestion
- Repair the outdated widget tests after validating the new fullscreen and focused-album interactions in real usage.

## 2026-05-06

### What Was Completed
- Rewrote `README.md` so the repository now describes the actual Memory Gallery product instead of the default Flutter starter text.
- Documented current features, Windows / Android layout differences, local run commands, validation commands, package outputs, and current project direction.
- Prepared the project for GitHub upload by checking git status, remotes, commit history, ignore rules, and untracked files.
- Verified the repo currently has no remote configured.
- Confirmed local git identity is configured as `mingy <mingyunbushou@outlook.com>`.
- Added persistent project status records required by `docs/AGENTS.md`.

### Files Changed
- `README.md`
- `docs/current_status.md`
- `docs/task_log.md`

### How To Verify
- Run `git status --short --branch`
- Run `git remote -v`
- Open `docs/current_status.md`
- Open `docs/task_log.md`

### Current Problem
- Upload to GitHub is blocked on missing target repository information and authentication path.

### Next Suggestion
- Decide whether to push to an existing GitHub repository URL or create a new repository under the desired account.
