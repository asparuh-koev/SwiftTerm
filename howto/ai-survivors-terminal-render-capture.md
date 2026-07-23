# AI Survivors terminal render capture

This fork adds a narrowly scoped macOS capture executable to SwiftTerm. It
observes the literal AppKit/CoreText draw calls and lossless per-cell pixels
produced for explicit synchronized-output frames. AI Survivors uses that text
artifact as an external rendering oracle for a small Hebrew, Arabic, fallback,
and terminal-primitive corpus.

The supported build is Apple silicon, macOS 13 or newer, Xcode Command Line
Tools with the macOS 15.4 SDK, `arm64-apple-macosx13.0`, and Swift 5 language
mode. The checked build intentionally uses direct `swiftc`; it does not depend
on SwiftPM.

## Quick start

From this repository:

```sh
scripts/check-toolchain
scripts/build-capture
.build/bin/terminal-render-capture self-test
```

The build and all generated test material remain below `.build/`.

## Provenance and integrity

`upstream` should name `https://github.com/migueldeicaza/SwiftTerm.git`. The
capture changes descend from upstream commit
`58915b1010d7dbc86d0e79dc2c40f0c183ccaf5b`; `NOTICE-terminal-render-capture.md`
describes the added files. `terminal-render-capture --version` prints the exact
fork commit embedded at build time. AI Survivors independently pins that value
in `render-capture/toolchain.json` and refuses a different binary.

For a clean checkout:

```sh
git remote get-url upstream
git merge-base --is-ancestor 58915b1010d7dbc86d0e79dc2c40f0c183ccaf5b HEAD
scripts/test-capture
```

## AI Survivors managed capture

Keep this checkout at `/Users/asparuhkoev/code/terminal-render-capture`, or set
`TERMINAL_RENDER_CAPTURE_BIN` to a matching prebuilt executable. In the sibling
AI Survivors repository:

```sh
scripts/terminal-render-capture self-test
scripts/terminal-render-capture capture --name latest --png
```

The second command enables the non-default Rust capture feature, prepares the
deterministic fixture through the production diff flusher, binds one ephemeral
loopback SSH listener, launches this executable as its client, and shuts down
both sides. It neither loads nor writes a player profile.

Results live below
`.artifacts/terminal-render-capture/special-characters-v1/<name>/`.
`capture.json` is the authority; `swiftterm.png` is optional review context.

## Direct SSH capture

For a program that already emits explicit DEC synchronized-output frames, pass
normal OpenSSH arguments after `--`. Direct mode is observational and does not
evaluate an AI Survivors scenario:

```sh
.build/bin/terminal-render-capture capture \
  --artifact .build/direct/capture.json \
  --direct --cols 100 --rows 20 \
  -- /usr/bin/ssh example-host
```

The tool delegates authentication, host verification, configuration, and keys
to `/usr/bin/ssh`; do not weaken those defaults for non-loopback hosts.

## Reading the text artifact

Each retained frame contains reconstructed cell sources, widths, links to
literal glyph or primitive draws, and a framebuffer digest. `glyph_atlas`
records actual font-file hashes, CoreText glyph IDs, positions, affine state,
lossless alpha masks, and Braille previews. `cell_tile_atlas` records lossless
RGBA tiles and previews. The draw records and tiles come from the same forced
CPU render.

`status.kind` says whether evidence is complete, incomplete, or truncated.
`summary.outcome.kind` then distinguishes portable assertion failure, an exact
baseline mismatch, an unbaselined environment, and a pass. Portable assertions
remain meaningful across different font environments. Exact comparison is
allowed only when the environment fingerprint matches.

To re-evaluate an artifact:

```sh
scripts/terminal-render-capture compare path/to/capture.json
```

## Baselines and bounded diagnostics

Capture and compare never bless output. After inspecting a complete portable
pass, update the environment-keyed baseline with the separate guarded command:

```sh
scripts/terminal-render-capture baseline-update path/to/capture.json
```

Use `--replace` only for an intentional replacement. Extend the AI-owned
scenario and assertions whenever covered characters are added.
`--retain-complete`, `--raw-wire`, and `--png` are bounded diagnostics for a focused
investigation, not routine test artifacts.

## Ghostty and Terminal.app observations

`compat` creates a uniquely titled window, requests Menlo 18, waits 250 ms,
captures only that window, records an observational JSON sidecar, and cleans up
only the window or app instance it created. It is not an exact oracle and never
claims glyph IDs. Use it only for a user-initiated rendering bug when
application-specific pixels add evidence.

Ghostty must be installed at `/Applications/Ghostty.app`. Terminal.app may ask
for Automation permission. Both may require Screen Recording permission.
Missing applications or permissions produce a redacted `unavailable` sidecar
and exit 4 without weakening the SwiftTerm result.

## Troubleshooting

- Toolchain check fails: install matching Command Line Tools and confirm
  `/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`.
- Pin mismatch: check out the commit recorded by AI Survivors, rebuild, and
  confirm `--version`; do not patch the pin around an uncommitted binary.
- Font unavailable: verify macOS can resolve `Menlo-Regular` at 18 points.
- SSH failure: run the same `/usr/bin/ssh` arguments directly and resolve trust
  or authentication there. Managed loopback captures intentionally disable
  host persistence and public-key probing only for their ephemeral listener.
- Incomplete or truncated evidence: inspect `status.reason` and `summary.
  utilization`; remove abandoned `.partial` output only after confirming no
  capture process remains.
- A leftover compatibility window is always a failure. Close the uniquely
  titled `ai-survivors-capture-*` window and report the cleanup defect.
