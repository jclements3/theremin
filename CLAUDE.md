# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A handoff bundle of standalone educational visualizations explaining the physics of a theremin (the zero beat / null, the capacitive pitch field, and pitch geometry). There is no application, build system, package manifest, or test suite — every deliverable is a single self-contained file with no dependencies or build step.

Contents:
- `theremin-handoff.tar.gz` — the distributable bundle. Extracting it produces `theremin-handoff/` containing the two source files below.
- `theremin-handoff/theremin_zero_beat_and_field.html` — a long-form illustrated explainer. Self-contained HTML; the only external references are Google Fonts. SVG figures are inlined, and a small inline `<script>` at the bottom generates the wave/beat path geometry procedurally (`wave()` helper) by setting the `d` attribute on `<path>` elements by id.
- `theremin-handoff/theremin_geometry_profile.svg` — a static annotated side-profile diagram (antenna height H, hand-to-antenna distance d, capacitive coupling, octave-count explainer). No script; all geometry is hand-authored coordinates.
- `Recording 2026-06-22 133513.mp4` — a ~360 MB screen recording (not part of the tarball; do not add it to the bundle).

## Working with the files

- View the HTML: open `theremin-handoff/theremin_zero_beat_and_field.html` directly in a browser (no server needed).
- View the SVG: open the `.svg` in a browser, or embed/inline it.
- Rebuild the bundle after editing: `tar czf theremin-handoff.tar.gz theremin-handoff/`

## Conventions

- These are presentation artifacts: keep them dependency-free and openable by double-click. Inline any new assets (SVG, CSS, JS) rather than adding external files or a build step.
- Both files share a deliberate visual language — a dark violet/amber palette and Space Grotesk / Space Mono / Inter typography in the HTML; a light slate palette in the SVG. Match the existing palette and type when editing.
- In the HTML, wave figures are not static markup — they are drawn at load time from the `wave(x, y, w, cycles, amp)` function and assigned by element id (`lf`/`lv`/`ld` for the "hand far / null" panel, `rf`/`rv`/`rd` for "hand near / tone"). Change the geometry there, not by hand-editing path `d` strings.
- The content makes specific physics claims (the audible note is the *difference* of two RF oscillators; the hand acts as a capacitor plate; iso-pitch shells bunch near the rod and spread toward the null; octave *count* comes from the oscillator circuit, not antenna height). Preserve this accuracy when revising copy.
