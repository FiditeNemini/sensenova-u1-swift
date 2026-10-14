# The artifact load transient is gone: int4 peaks 12.2 GB at 1024² (was 14.7)

**2026-10-14, Mac Studio (Mac17,14), M5 Max 128 GB, release `sensenova-cli`, GPU otherwise idle.**
Follow-up to AB-R-0533 / AB-R-0534 and the tier split AB-D-0141, where SenseNova int4 was kept out of the 16 GB
Generative Fill tier only by its 14.7 GB MLX load peak against the tier's 12.7 GB limit, with an active set of
11.2 GB.

## Cause

`WeightLoading.loadArtifact` built the model, called `quantizeStreams` to turn the layer Linears into
QuantizedLinears, and that function ended with `eval(model)`: it materialized the whole **random-init** model,
quantizing lazily generated bf16 weights into 11 GB of quantized tensors that the artifact's `update` then threw
away. The bf16 intermediates alive during that one eval are the 3.5 GB above the floor. The shards themselves load
lazily and the final `eval(model)` materializes only the artifact's tensors.

## Change

`quantizeStreams(_:bits:groupSize:evaluate:)` takes `evaluate` (default `true`, the conversion path's behaviour);
`loadArtifact` passes `false`, so the quantization is structural and nothing is evaluated before the artifact's
parameters are in place. One file, `Sources/SenseNovaU1/WeightLoading.swift`.

## Measured (same fixture, prompt and seed 7 as `memory_arms.log` in the bake-off)

| Tier | Size | Load peak before → after | Run peak before → after | Process footprint peak before → after | Run time |
|---|---|---|---|---|---|
| 8step-v2-4bit | 1024² | 14.73 → **11.24 GB** (= floor) | 14.73 → **12.20 GB** | 24.1 → 13.9 GB | 3.9 s → 3.9 s |
| 8step-v2-4bit | 768² | 14.73 → 11.23 GB | 14.73 → **11.93 GB** | 23.5 → 13.3 GB | 2.3 s → 2.3 s |
| 8step-v2-8bit | 1024² | 22.46 → 18.96 GB | 22.46 → **19.86 GB** | 32.0 → 21.9 GB | 4.0 s → 4.3 s |
| 8step-v2-8bit | 768² | 22.92 → 18.96 GB | 22.92 → 19.66 GB | 31.5 → 21.4 GB | 2.5 s → 2.4 s |

- Load peak and run peak are `GPU.peakMemory` as the CLI prints them; process footprint is `time -l`'s
  "peak memory footprint". The first 1024² run after the rebuild took 8.9 s (Metal warm-up); the second, 3.9 s.
- **Parity:** the after-change outputs are **bit-identical** to the pre-change outputs at the same seed for int4
  1024², int4 768² and int8 768² (`parity.txt`). Nothing about the weights or the forward changed.
- The denoise's own activation at 1024² is about 1.0 GB int4 / 0.9 GB int8 above the floor.

## What it means for the tiers

SenseNova 8step-v2-4bit now fits a 12.7 GB MLX limit for a 1024² fill window with 0.5 GB to spare (11.9 GB at
768²). That is tight: the editor's other MLX residents (segmentation, LaMa) would have to be evicted first, and
the 0.5 GB has not been tried on a real 16 GB machine or under the 12.7 GB emulation. AB-D-0141 kept 16 GB on
Klein-4B int4 encoder-evicted with the window capped at 768² (8.9 GB); whether SenseNova takes 16 GB on this
measurement is the operator's call.

The engine wrapper's declared footprints are unchanged (resident 12.2 GB int4 / 20.5 GB int8 with the 2048²
activation envelope); the note in `SenseNovaU1Package.swift` records the new load behaviour.

## Files

`after.log` (the four runs plus the re-timed 1024² int4), `parity.txt`, `after_*.npy` are not kept (large).

**Tests:** `swift test -c release -Xswiftc -enable-testing --filter "ConformanceTests|ArtifactRoundTripTests"`:
ArtifactRoundTripTests 2/2 (the quantized artifact still self-describes and round-trips exactly), ConformanceTests
10/10.
