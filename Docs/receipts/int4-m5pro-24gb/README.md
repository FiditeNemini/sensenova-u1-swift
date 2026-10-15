# SenseNova 8step-v2-4bit on a 24 GB M5 Pro: the real 24 GB tier numbers, and the chip floor

**2026-10-14, MacBook Pro (M5 Pro, 16-core GPU, 24 GB), macOS 27.2, release `sensenova-cli` built on this machine at
v0.5.2 (be1d8ff), GPU otherwise idle (largest other resident 0.5 GB).** The artifact is the Mac Studio's
`weights/artifacts/SenseNova-U1.5-8B-MoT-8step-v2-4bit`, copied over SMB and verified file-for-file against the source.
Same fixtures, prompt and seed 7 as the bake-off's `memory_arms.sh`; one fresh process per row under `/usr/bin/time -l`
(in-process residue makes back-to-back runs unusable, AB-R-0154); `run.log` is the CLI output verbatim with swap
before and after each row. This is the smaller-chip receipt the manifest's `chipFloor: .max` comment asked for, the
run AB-A-0181 asked for before the floor is relaxed, and the "real M5 Pro 24 GB numbers" AB-D-0141 carries as owed.

## Runs

| Run | Load | Floor | Active at step 8 | MLX peak | Step | Total | Process footprint peak | M5 Max (AB-R-0536 / AB-R-0537) |
|---|---|---|---|---|---|---|---|---|
| 1024² edit | 1.7 s | 11,235 MiB | 11,517 MiB | **12,203 MiB (12.80 GB)** | **1.10 s** | 8.8 s | 13.88 GB | 0.47 s / 3.9 s / 12,217 MiB |
| 1024² edit, repeat | 1.6 s | 11,235 | 11,517 | 12,203 | 1.09 s | 8.7 s | 13.87 GB | — |
| 768² edit | 1.5 s | 11,230 | 11,410 | 11,931 (12.51 GB) | 0.62 s | 5.0 s | 13.21 GB | 0.29 s / 2.3 s / 11,931 |
| 2048² edit | 1.6 s | 11,235 | 11,661 | 12,569 (13.18 GB) | 4.33 s | 34.6 s | 15.01 GB | 1.82 s / 14.6 s / 12,569 |
| 1024² T2I | 1.5 s | 11,223 | 11,315 | 11,926 (12.50 GB) | 0.97 s | 7.8 s | 13.02 GB | README: 3.2 s total |
| 2048² T2I | 1.5 s | 11,223 | 11,459 | 12,364 (12.96 GB) | 4.16 s | 33.3 s | 14.18 GB | README: 15.8 s total |
| 1024² edit, MLX limit 12,116 MiB | 1.5 s | 11,235 | 11,517 | 12,145 (12.73 GB) | 1.09 s | 8.7 s | 12.95 GB | 0.47 s / 3.8 s / 12,145 |
| 1024² edit, warm-up (first run after the build) | 2.5 s | 11,235 | 11,517 | 12,203 | 1.53 s | 12.2 s | 13.84 GB | 8.9 s first run |

Floor and active are `GPU.activeMemory`, MLX peak is `GPU.peakMemory`, as the CLI prints them (MiB); process footprint
is `time -l`'s "peak memory footprint". Prompts: the bake-off's fill instruction for the edits, the README's mountain
lake for T2I. 8 steps, cfg 1, seed 7 throughout.

## Findings

1. **The memory picture is the Max's, to the MiB.** Floor 11,235 MiB; peaks 12,203 at 1024², 11,931 at 768², 12,569 at
   2048², 12,145 under the 12,116 MiB cap: the same figures AB-R-0536 and AB-R-0537 report on the M5 Max. The working set
   is a property of the artifact and the window, not of the chip. Nothing throws, nothing is refused.
2. **Speed scales with the GPU, not with pressure.** Every row is 2.1–2.4× the Max's step time (1024² 1.10 vs 0.47 s,
   768² 0.62 vs 0.29, 2048² 4.33 vs 1.82), in line with a 16-core GPU against the Max's. The 12,116 MiB cap changes
   nothing (1.09 s/step, same as uncapped), the repeat reproduces the first run within 0.01 s/step, and the throttling
   signature of AB-R-0537 (2× per step with a 1 GiB overrun) does not appear. A 1024² fill is 8.7–8.8 s warm on this
   machine and a 768² fill 5.0 s; for scale, Klein bf16 took 23.6 s at 1024² on the Max (`memory_arms.log`).
3. **Determinism holds on this chip.** The warm-up, measured, repeat and capped 1024² outputs are bit-identical
   (`parity.txt`); no output carries a NaN or inf; the renders are right (`thumbs/`: the dog sits on the pavement in the
   picture's light, the rest of the frame preserved). Cross-machine parity with the Max is not checkable because its
   outputs were not kept.
4. **The real-Mac pressure fact: a load pushes about 1.3 GB to swap, once.** Swap used went 0.15 → 1.43 GB during the
   first load and 1.43 → 1.69 GB during the 2048² edit (15.0 GB process footprint); every other row left it flat and no
   step slowed. With 24 GB and nothing else large resident, the process's 13.9–15.0 GB peak footprint is what macOS
   compresses and swaps around. In the editor that swap lands on the editor's own pages, and the other MLX residents
   are charged against the same budget, so AB-D-0141's evict-first condition applies at 24 GB too.
5. **Admission on this machine passes as declared.** Metal's `recommendedMaxWorkingSetSize` here is 17.76 GiB =
   19.07 GB decimal, the governor's budget (about 74 % of 24 GiB). The int4 tier's declaration, 12.2 + 4.5 GB =
   16.7 GB, fits with 2.4 GB spare, and the measured 1024² peak is 6.3 GB under the budget. int8 does not fit on 24 GB
   by either measure (declared 24.7 GB; measured 19.9–20.8 GB peak), as AB-D-0141's 32 GB+ line already says.
6. **The engine's host detection is permissive today.** `DeviceProfile.current()` (mlx-engine-swift 0.50.0 through
   v0.67.0) returns `chipTier: .max` on every Apple Silicon host, with a comment to parse the brand string "when a real
   gate needs it", and `MLXServeEngine.init` takes `device:` defaulting to it. So `chipFloor: .max` has refused nobody
   so far, and the moment detection is refined it would refuse this M5 Pro. The floor has to follow the receipts, not
   the detector's leniency.

## Verdict

**`chipFloor` moves from `.max` to `.pro`** in this change. The int4 tier runs on a Pro-class chip with the Max's
memory profile and GPU-scaled speed, and the 24 GB Generative Fill tier (8step-v2-4bit, window ≤ 1024², AB-D-0141) is
admitted on this M5 Pro as declared. Base chips remain unmeasured, so the floor stays at `.pro` rather than disappearing;
a base-chip receipt relaxes it further. The 16 GB tier question (AB-T-0278: a separate 16 GB footprint declaration, then
a real 16 GB Mac) is untouched by this receipt — a 24 GB machine says nothing about a 16 GB budget's swap behaviour —
except for one data point: on a Pro-class GPU the capped 1024² run keeps the Max's working set (12,145 MiB) and does
not throttle.

## Files

`run.log` (the eight runs as printed, with swap before and after each), `parity.txt`, `thumbs/` (512-px JPEGs of the
1024², 768² and 2048² edits and both T2I renders; full outputs not kept, large), `run_matrix.sh` (the exact
invocations), `npy2png.swift` (the converter used for the eyeball and the NaN count; this machine has no numpy).

**Tests:** `swift test -c release -Xswiftc -enable-testing --filter ConformanceTests` after the floor change: 10 tests, 0 failures. Bridge receipt: AB-R-0551.
