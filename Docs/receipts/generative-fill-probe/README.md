# Generative Fill / Expand probe on the 8-step V2 tiers (AB-A-0166)

**2026-10-14, Mac Studio (Mac17,14), M5 Max 128 GB, release `sensenova-cli` at 9d20124, GPU otherwise idle.**
Five runs, not a bake-off. The question was whether SenseNova-U1.5 can serve the Image Engine's prompted
fill / extend route at all, and at what memory, before it is weighed against FLUX.2-klein-4B for the
PixelAgencyEditor Generative Fill tiers (AB-A-0166, AB-A-0173, AB-T-0246).

## Route

Exactly the Image Engine's generative fill route (`pixel-agency-image-engine` `RunPlan.paint`): the region
is painted bright magenta (255, 0, 255) on the picture, the model is given the whole picture and the engine's
own instruction, the result is composited back through the mask. No harmonize or feather here (the engine
adds both), so the seams below are the raw composite, the worst case.

- Fill: "Replace the bright magenta area with a small wooden fishing boat. Match the picture's lighting,
  perspective and style, and keep everything else unchanged."
- Seamless fill (no prompt): "Fill the bright magenta area so it blends seamlessly into the rest of the
  picture, as if nothing had been there. Keep everything else unchanged."
- Expand: "Replace the bright magenta area at the right edge with a seamless continuation of the scene.
  Keep everything else unchanged."

Fixture: `Agropoli 02.jpg`, Bernard Gagnon, CC BY 4.0 (commons-sr corpus, `exteriors/24e4d6d7a1`), as a
1024² centre crop, a 1536×1024 resize, and the crop padded 256 px on the right (1280×1024). Region 320² on
the square, 360² on the non-square. 8 steps, cfg 1, seed 42, output at the input's size (`--width/--height`).

## Results

| Case | Tier | Size | Warm time | MLX peak | Process RSS | Marker left | Drift outside mask |
|---|---|---|---|---|---|---|---|
| Fill, boat | 8step-v2-4bit | 1024² | 7.2 s (first run, Metal warm-up) | 14.73 GB | 12.0 GB | 0 % | 10.2 MAE / 22.7 dB |
| Fill, boat | 8step-v2-4bit | 1536×1024 | 5.5 s | 14.74 GB | 12.0 GB | 0 % | 8.5 MAE / 24.2 dB |
| Expand right | 8step-v2-4bit | 1280×1024 | 4.6 s | 14.73 GB | 12.0 GB | 0 % | 8.4 MAE / 25.2 dB |
| Seamless fill | 8step-v2-4bit | 1024² | 3.7 s | 14.73 GB | 12.0 GB | 0 % | 8.1 MAE / 25.5 dB |
| Fill, boat | 8step-v2-8bit | 1024² | 4.0 s | 22.46 GB | 20.1 GB | 0 % | 11.2 MAE / 22.4 dB |

- **Marker left** is the engine's `paintingProblem` test: share of the region still purple-dominant
  (threshold 25 %). Every run painted the whole region; nothing was handed back.
- **Drift outside mask** is the raw result against the original outside the region. SenseNova re-renders
  the whole picture, slightly brighter and warmer here, so the hard composite shows a tone step at the
  region's edge (`seams.jpg`). The engine's harmonize + feather exists for exactly this; the adapter must
  do the same.
- Load: 4.7 s int4. Active after load 11.2 GB int4 / 19.0 GB int8; the MLX **peak is the load transient**
  (+3.5 GB), the 1024² denoise itself adds about 0.3 GB. `time -l` reported a process "peak memory
  footprint" of 24.4 GB int4 / 32.0 GB int8, a file-backed load transient that the in-app phys measurement
  should confirm or dismiss before any tier is declared.
- Non-square input ran at its own aspect (`smart_resize` keeps it); no squash.
- Expand continued the hill, sand and pier coherently; the seamless fill rebuilt the water; both boats sit in
  the picture's light. The boats' bows and reflections extend past the rectangle in the raw result, which the
  rectangular composite clips: a real selection would be feathered and padded, as the ask specifies.

## Reading for the tiers (16 / 24 / 32 GB+)

- **16 GB (12.7 GB MLX limit):** not admissible today. int4 peaks at 14.7 GB on load; active after load is
  11.2 GB, so trimming the load transient would be a prerequisite, and 1.5 GB of headroom under the editor
  is thin. Klein-4B with the encoder evicted (phys peak 10.06 GB at 768²) is the only candidate that fits.
- **24 GB:** int4 fits with headroom (14.7 GB peak, 12.0 GB RSS). 1024² fill in about 4 s warm against
  Klein's 17.9 s in the engine's tier bench; handles non-square natively where Klein squashes (AB-T-0217).
- **32 GB+:** int8 (22.5 GB peak), which reproduces the bf16 merge at cos 0.995 (AB-R-0490).

The V2 8-step adapter is what makes this a tier at all: it runs the edit cfg-free in 8 steps (3.7–7 s) where
the 50-step base recipe takes 169 s at 2048² (AB-R-0490). It changes nothing about memory.

## Files

- `sheet.jpg`: per row, the marked input, the raw result, the composite through the mask (rows: int4 fill,
  int8 fill, seamless, non-square, expand).
- `seams.jpg`: full-resolution crops of the composite edges (int4 fill, expand, non-square).
- `make_fixtures.py`, `tonpng.py`: fixture builder and the npy → png + marker/drift checker.
- `metrics.txt`: the CLI and checker output verbatim.
