# 16 GB emulation: SenseNova 8step-v2-4bit under a 12.7 GB MLX limit

**2026-10-14, Mac Studio (Mac17,14), M5 Max 128 GB, release `sensenova-cli` after c1e77da (the load-transient fix,
AB-R-0536), GPU otherwise idle.** The condition AB-D-0141 attached to moving the 16 GB Generative Fill tier to
SenseNova int4: confirm the headroom under the 16 GB budget before the tier ships.

## What "12.7 GB" is, and what the emulation can and cannot show

- The engine's budget on a 16 GB Mac is Metal's `recommendedMaxWorkingSetSize`, about 74 % of RAM on macOS 26
  (MLXEngine `MemoryGovernor.forDevice`): **12.7 GB decimal = 12,116 MiB.** The CLI prints MiB. This Mac's own
  figure is 115.4 GB (84 % of 128 GiB), so nothing here is a real 16 GB machine.
- MLX's memory limit is **soft** (BRIDGE-036, mlx-swift `Memory.memoryLimit`): past it, allocations wait for
  scheduled work instead of failing. Setting it, with the cache limit at the same figure, shows the true working
  set and how much a run slows when squeezed; it cannot reproduce a 16 GB Mac's swap or jetsam. The CLI gained
  `--mlx-limit-mb` and `--ballast-mb` (an N MiB MLX array kept alive, a stand-in for another resident model).
- Separately, the engine wires residency at `min(recommended, total − clamp(total/8, 6 GiB, 16 GiB))`, which on a
  16 GB Mac is **10 GiB**: SenseNova's 11.2 GiB floor can never be fully wired there. Wiring is a residency hint,
  not admission, so that is a pressure-behaviour fact, not a refusal.

## Runs (same fixture, prompt and seed 7 as the bake-off; `after.log` of AB-R-0536 is the unlimited reference)

| Run | Limit | Floor | Active at step 8 | MLX peak | Step time | Total | Output vs unlimited |
|---|---|---|---|---|---|---|---|
| 1024² edit | 12,116 MiB | 11,235 MiB | 11,573 MiB | **12,145 MiB (12.73 GB)** | 0.47 s | 3.8 s | bit-identical |
| 768² edit | 12,116 MiB | 11,230 | 11,410 | **11,931 MiB (12.51 GB)** | 0.29 s | 2.3 s | bit-identical |
| 1024² + 1 GiB ballast | 12,116 MiB | 12,259 | 12,556 | 12,650 MiB (13.26 GB) | **0.96 s** | 7.7 s | bit-identical |
| 768² + 1 GiB ballast | 12,116 MiB | 12,254 | 12,434 | 12,509 MiB (13.12 GB) | **0.72 s** | 5.8 s | bit-identical |
| 1024² edit | 13,005 MiB (12.7 GiB) | 11,235 | 11,550 | 12,217 MiB | 0.47 s | 3.8 s | bit-identical |
| 2048² edit | 12,116 MiB | 11,235 | 11,661 | 12,193 MiB (12.78 GB) | 1.80 s | 14.4 s | bit-identical |
| 2048² edit, unlimited | — | 11,235 | 11,661 | 12,569 MiB | 1.82 s | 14.6 s | (reference) |

- Every run completed; nothing threw. The outputs are bit-identical to the unlimited runs in every case
  (`parity.txt`): the limit changes scheduling, never numerics.
- **The floor is the whole story.** With the cache capped, the window size barely moves the peak: 768² 12.51 GB,
  1024² 12.73 GB, 2048² 12.78 GB. The denoise's working set is 0.2–0.4 GiB above the 11.2 GiB floor; the rest
  of the peak is transient allocation.
- **At 1024² the peak is 30 MB over the 12.7 GB budget; at 768² it is 0.19 GB under.** MLX let both through
  because the limit is soft.
- **One extra gigabyte resident halves the speed.** With a 1 GiB ballast the working set is 0.4–0.5 GB over the
  limit and MLX throttles every step 2–2.5× (0.47 → 0.96 s/step at 1024²). On a real 16 GB Mac the same overrun
  lands in compressed memory or swap, which is the failure mode the tier would show: not a crash, a 2× or worse
  slowdown, and then the OS reclaiming pages from the editor itself.

## Admission is the harder test

The engine does not look at measurements; it charges the package's declared footprint against the budget
(`MemoryGovernor.canFit`): `residentBytes` plus the run's `peakActivationBytes`. The int4 tier declares
12.2 GB + 4.5 GB (the 2048² envelope) = 16.7 GB, so **as declared, SenseNova int4 is refused on every 16 GB Mac
regardless of these runs.** Declaring honestly for a capped window (resident 11.8 GB measured floor, activation
1.0 GB at 1024² or 0.75 GB at 768²) gives 12.8 GB or 12.55 GB against 12.7: still refused at 1024², admitted at
768² with 0.15 GB to spare, and only after the editor's other MLX residents are evicted, since they are charged
against the same budget.

## Verdict

**Not confirmed at 1024².** SenseNova 8step-v2-4bit's working set sits on the 16 GB budget line for any window
(12.5–12.8 GB against 12.7), with no room for the editor's own residents, and the package's declared footprint
would have to become a separate 16 GB variant (768² window envelope, resident at the measured floor) for the
engine to admit it at all. The emulation that can be run here passes the 768² case by 0.19 GB measured and
0.15 GB declared; that is not headroom a tier should ship on without a real 16 GB machine.

Options for the operator, in order of safety:
1. **16 GB back to Klein-4B int4, encoder evicted, window ≤ 768²** (AB-R-0534: 8.9 GB peak, 3.8 GB of headroom);
   SenseNova from 24 GB up, as the bake-off's original split.
2. SenseNova int4 at 16 GB with the window capped at **768²**, a new 16 GB footprint declaration, and the editor
   evicting everything else first; confirm on a real 16 GB Mac before shipping.
3. A lighter SenseNova tier for 16 GB (a declared opt-in 3-bit or mixed quant, about 2.5 GB off the floor), a
   separate conversion and A/B, not a setting.

## Files

`run.log` (the seven runs as printed), `parity.txt`. Outputs are not kept (large). CLI flags: `--mlx-limit-mb`,
`--ballast-mb` in `Sources/sensenova-cli/main.swift`.
