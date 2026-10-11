# 8-step V2 adapter A/B — 2026-10-11 (AB-T-0228)

Fixed seed 42, 1024², 8 steps, cfg 1, five prompts (`prompts.txt`), on an M5 Max with the
`8step-{8bit,4bit}` (V1) and `8step-v2-{8bit,4bit}` artifacts converted from the pinned
`07d76f61` base with `sensenova-cli --weights <base> --lora <adapter> --quant N --convert`.
V2 adapter: `sensenova/SenseNova-U1.5-8B-MoT-LoRAs` @ `f33b8fe`, sha256 `f4190cab…6f201`,
identical 882-tensor key set / shapes / alpha 8.0 to V1. `--diff-artifacts` V1 vs V2 (8-bit):
exactly 882 tensors differ (294 gen-stream projections × weight/scales/biases), nothing else.

`metrics.txt` is `ab_metrics.py` over the renders; `AB_<quant>_<prompt>.png` are V1 (left) | V2 (right).

Mean Δ(V2−V1), 8-bit: saturation −0.070, RMS contrast −0.045, grad p99 −0.047 (−25 %),
clip_lo −8.4 pp, clip_hi −12.7 pp, luminance +0.001, high-frequency share flat. 4-bit: the same
direction, slightly larger. cos(V1,V2) 0.86–0.99 (8-bit): same composition, different tone.
V2 int8 vs V2 bf16 merge-at-load (lake): cos 0.9948, 30.9 dB. V2 int4: cos 0.9760, 24.2 dB.
V2 int8-vs-int4 cos 0.88–0.98 against V1's 0.82–0.96 — the V2 adapter is more quant-robust.

Timing, idle GPU: 8-bit 1024² 3.3 s (0.41 s/step) at 22.4 GB peak, 2048² 13.4 s; 4-bit 3.2 s
at 14.7 GB. (The same renders took 9–13 s while a `swift build`/test ran alongside and four
artifacts cycled through the page cache — contention, not a regression.)

Eyeball: the portrait's orange, crushed skin is natural in V2; the poster's garbled overlapping
"CONCERT" is clean type (V2 drops the word rather than mangle it); the watercolour reads as
watercolour. V2 is the better default for the fast tier.
