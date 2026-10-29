# retrobox-mangohud

Packaging for the MangoHud that [Retrobox](https://github.com/manu-romero-411/retrobox-core)
uses for its HUD and bezel overlay: upstream
[MangoHud](https://github.com/flightlessmango/MangoHud) plus a patch series
(`background_image` / `image` support), built as `.deb` and `.rpm` by GitHub
Actions.

Nothing from upstream is vendored here. Each build fetches an upstream
release, applies `patches/*.patch`, compiles it, packages it and tests the
package in a clean container.

## Packages

The set of distributions is not written in the workflow: each run resolves it
(`scripts/resolve-matrix.py`, from endoflife.date, only releases whose container
image already exists) as the **latest Debian stable, the last two Ubuntu LTS and
the last two Fedora releases**. Today that is:

| Distribution          | Format | Built on                       |
|-----------------------|--------|--------------------------------|
| Debian 13             | `.deb` | `debian:trixie`                |
| Ubuntu 24.04 / 26.04  | `.deb` | `ubuntu:24.04`, `ubuntu:26.04` |
| Fedora 43 / 44        | `.rpm` | `fedora:43`, `fedora:44`       |

Download the file for your distribution from the
[latest release](../../releases/latest). The package depends on `retrobox-core`.

### File names and versions

Each family names its packages its own way, and the version carries the UTC
date and time **of the build** (when it was packaged, not when upstream
committed that version):

| Format | Convention | Example |
|--------|------------|---------|
| `.deb` | `<package>_<version>_<arch>.deb` | `retrobox-mangohud_0.8.4-12.20260527.140811~ubuntu24.04_amd64.deb` |
| `.rpm` | `<name>-<version>-<release>.<arch>.rpm` | `retrobox-mangohud-0.8.4-12.20260527.140811.fc44.aarch64.rpm` |

* `0.8.4` is the upstream release tag (the **latest stable one**). A build of a
  branch or a commit, by manual dispatch, is versioned `<YYYYMMDD>.<HHMMSS>` of
  the build instead.
* `12` is the run number of the workflow; `20260527.140811` is
  `YYYYMMDD.HHMMSS` of the build, in UTC. All the packages of one release
  share it (it is fixed once per workflow run). (An underscore, as in the release tag, is not allowed in a
  Debian version, so the dot is used.)
* The distribution is in the version of the `.deb` (`~deb13`, `~ubuntu24.04`,
  `~ubuntu26.04`) and in the `dist` tag of the `.rpm` (`.fc43`, `.fc44`): the
  packages differ per distribution, because their library dependencies do.
  GitHub shows the `~` of a `.deb` as a `.` in the name of the downloadable file.
* The architecture, as each family writes it:

| Target | `.deb` (Debian, Ubuntu) | `.rpm` (Fedora) | Runs on |
|--------|-------------------------|-----------------|---------|
| x86-64 | `amd64` | `x86_64` | any 64-bit PC |
| 64-bit ARM | `arm64` | `aarch64` | ARM64 machines |

There are no x86-64-v3 builds for now. `scripts/build.sh` and the packaging
scripts still accept `MICROARCH=v3` for local builds (the architecture then
reads `amd64v3` / `x86_64_v3`).

The release itself is tagged `build-v0.8.4-20260527_140811-<commit>-<hash>` (same build
date and time, written `YYYYMMDD_HHMMSS`). The full commit id and the date of
the upstream commit are in `/usr/share/doc/retrobox-mangohud/BUILDINFO`.

## What gets installed

Everything lives in a **private prefix**, so it can sit next to the MangoHud
of the distribution without either shadowing the other. The only files outside
it are the Vulkan layer manifest (the loader never looks inside the prefix) and
the `environment.d` file:

| Path | Content |
|------|---------|
| `/opt/retrobox/libexec/mangohud/bin/mangohud` | wrapper (absolute libdir baked in, no `$LIB`) |
| `/opt/retrobox/libexec/mangohud/lib/mangohud/lib64/` | `libMangoHud.so` and friends |
| `/usr/share/vulkan/implicit_layer.d/RetroboxMangoHud.<arch>.json` | Vulkan layer manifest, in the directory the Vulkan loader searches; layer `VK_LAYER_RETROBOX_MANGOHUD_overlay_<arch>`, enabled by `RETROBOX_MANGOHUD=1`, disabled by `RETROBOX_MANGOHUD_DISABLE`; its `library_path` points to the private library |
| `/usr/lib/environment.d/64-retrobox-mangohud.conf` | keeps the Retrobox layer off outside Retrobox |

Upstream's own `MangoHud.<arch>.json` layer is not installed. Nothing is
registered with `ldconfig`.

**64-bit only**: Retrobox wraps 64-bit emulators. A 32-bit companion build is
not part of this package.

## Patches

`patches/` is the series applied, in file-name order, to a clean upstream
release, plus `patches/BASE`, the tag they were made against. Batocera's
patches come first and the Retrobox ones on top, as in `retrobox-core`'s
installer (`setup/utils/mangohud.sh`):

| Patch | Origin | What it does |
|-------|--------|--------------|
| `0001` | Batocera `003-add-sm8250` | CPU temperature from `cpu0_thermal` (Batocera RPMini, SM8250) |
| `0002` | Batocera `004-Add-Qcom-Bat-Support` | recognise the `qcom-battmgr-bat` battery |
| `0003` | Batocera `005-hotkeys` | a single default hotkey, `Shift_R+Undo` (`toggle_hud`); the rest are unbound |
| `0004` | Batocera `006-no-csv-file` | no log summary CSV when logging stops |
| `0005` | Batocera `007-msm-gpu-stats` | GPU statistics on the mainline `msm` driver |
| `0006` | Batocera `008-mali-profiling` | switch on the `panfrost`/`panthor` profiling |
| `0007` | Nicolas Adenis-Lamarre | `stb_image`, `stb_image_resize2` and the texture loader |
| `0008` | Retrobox | the `image`, `image_max_width` and `background_image` options (OpenGL and Vulkan) |

Batocera's `001-no-mangohud.json` is **not** used: its only effect is to stop
MangoHud's own Vulkan layer from being installed, and this package already
replaces that layer with the Retrobox one (see `scripts/stage.sh`).

The patches are normalised: each applies exactly to the tag in `patches/BASE`
and carries full blob ids, which is what the 3-way fallback below needs
(Batocera's originals do not apply with `git apply` and have no blob ids).
Comments and commit messages are in English.

### Changing the series

* **Batocera adds or changes a patch** in `package/batocera/utils/mangohud/`:
  apply it to a clean checkout of `patches/BASE` (`patch -p1 --fuzz=3` if it
  was made for another version), commit it with the original author and a
  `Taken from batocera.linux, ...` line, and export it with
  `git format-patch -1 --full-index --no-signature --zero-commit`. Name it
  `NNNN-batocera-<what>.patch`, before the Retrobox ones.
* **A Retrobox change:** commit it on top of the series applied to a clean
  checkout and export it the same way. Keep Batocera's changes out of it, so
  the origin (and the licence) of each patch stays clear.
* **A new upstream release:** nothing to do if the patches still merge; if not,
  the build names the patch and the file, see below.

### How it copes with new upstream releases

`scripts/fetch.sh` applies each patch as it is when it fits. When it does not,
it falls back to a **3-way merge** against `patches/BASE`, which is fetched
alongside the target, so a patch still applies if upstream moved or edited
code near it. Because the patches are per file, a patch that cannot be merged
names the file that needs attention, and the other patches are not affected.

## The workflow (`.github/workflows/build.yml`)

1. `resolve` – picks the upstream ref (latest stable release tag, or the one
   you give), computes the release tag
   (`build-<ref>-<build date>-<upstream commit>-<hash of this repo's build inputs>`), stops if a
   release of that same commit and inputs already exists (whatever its date), and checks that the patches apply.
2. `build` – one job per distribution **and architecture** (2 per distribution, `arm64`/`aarch64` on native ARM runners; the distributions come from `scripts/resolve-matrix.py`): dependencies, fetch, patch, compile,
   package.
3. `test` – installs each package, on a runner of its own architecture, in a **clean** container (with a stub
   `retrobox-core`) and checks the wrapper, the layer, that nothing leaks out
   of the private prefix and that every library resolves.
4. `publish` – creates the GitHub release.
5. `notify` – on a failed scheduled run, opens one `upstream-drift` issue.

It runs **every two months, on the 13th** (January, March, May, July,
September, November), **on demand** from Actions → build → *Run workflow*
(with an optional upstream ref), and when patches or packaging change. Pull
requests build and test but never publish. With an empty `patches/` it never
publishes either.

## Building locally

```bash
sudo scripts/install-build-deps.sh                  # Debian/Ubuntu or Fedora
scripts/fetch.sh work/src                           # --ref <tag|branch|sha>
scripts/build.sh work/src                           # MICROARCH=v3 for a local x86-64-v3 build
PKG_REVISION=1 scripts/build-deb.sh work/src dist   # or build-rpm.sh (same MICROARCH)
```

## Licensing

* This repository (scripts, workflow, packaging) is MIT, see `LICENSE`.
* MangoHud is MIT. The Retrobox patch `0008` is a derivative work of it and is
  MIT as well, so upstream's copyright notice is kept: it is installed,
  verbatim, in `/usr/share/doc/retrobox-mangohud/licenses/`.
* **Batocera.** Patches `0001` to `0006` come from `batocera.linux`, which is
  LGPL-3.0-or-later (The Batocera Team). Their added lines keep that licence;
  `copyright`, the rpm `License:` field and `licenses/LGPL-3.0.txt` +
  `GPL-3.0.txt` say so. The patches are in this repository and the libraries
  are shared objects that can be replaced, so the LGPL conditions are met.
* **`0007`** (Nicolas Adenis-Lamarre, 2021) states no licence of its own; it is
  treated as MIT like MangoHud. It adds the `stb_image` and `stb_image_resize2`
  headers (MIT or public domain, your choice), whose notices are installed.
  **Do not add code from a project with an incompatible licence without
  checking it first**: the whole library would be affected.
* MangoHud statically links imgui, implot, spdlog (with {fmt}) and the Vulkan
  headers and utility libraries, and embeds third-party code (elfhacks/Zlib,
  ghc::filesystem/MIT, Khronos headers, Mesa code, the NVIDIA NVML header, stb)
  and the Fork Awesome font (OFL-1.1). All of it is described in
  `packaging/copyright`; the verbatim licence files and notices are copied
  from the source tree at build time into `licenses/`.
* `scripts/check-licenses.sh` runs in every build and **fails** when upstream
  adds a subproject, a vendored header, an embedded font or a source file with
  a copyright notice that is not listed in `packaging/licenses-reviewed.txt`.
  This will happen, for instance, with newer releases that add `vkroots` or
  `vk-bootstrap`. Read the licence of the new component, describe it in
  `packaging/copyright`, and add it to the list.
  `ALLOW_UNREVIEWED_LICENSES=1` downgrades the failure to a warning for test
  builds only.
* Known gap: `src/font_default.h` and `src/font_unispace.c` embed fonts whose
  origin and licence upstream does not document.
