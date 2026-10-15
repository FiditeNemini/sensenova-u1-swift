#!/bin/zsh
# SenseNova 8step-v2-4bit on the MacBook Pro (M5 Pro, 24 GB): the real 24 GB tier numbers.
# One fresh process per row (in-process residue makes back-to-back runs unusable, AB-R-0154), GPU otherwise idle.
set -u
R="$HOME/Development/sensenova-m5pro-run"
CLI="$HOME/Development/sensenova-u1-swift/.build/release/sensenova-cli"
W="$HOME/Models/SenseNova-U1.5-8B-MoT-8step-v2-4bit"
P="Replace the bright magenta area with a brown dog sitting on the pavement. Match the picture's lighting, perspective and style, and keep everything else unchanged."
T2I="A cinematic mountain lake at sunrise, realistic photography."
LOG="$R/run.log"
cd "$R" || exit 1
{
  echo "# sensenova-cli v0.5.2 (be1d8ff) release build on this machine, 8step-v2-4bit, 8 steps, cfg 1, seed 7, stopsign fixtures (bake-off inputs, prompt verbatim)"
  echo "# host: $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion), $(date)"
} > "$LOG"
run() {
  local name="$1"; shift
  local slug="${name// /_}"
  echo "=== $name" | tee -a "$LOG"
  echo "swap before: $(sysctl -n vm.swapusage)" >> "$LOG"
  /usr/bin/time -l "$@" > "$R/logs/$slug.full.log" 2>&1
  echo "exit=$?" >> "$LOG"
  grep -E '^\[cli\]|maximum resident|peak memory footprint| real ' "$R/logs/$slug.full.log" | tee -a "$LOG"
  echo "swap after:  $(sysctl -n vm.swapusage)" >> "$LOG"
}
run "warmup int4 1024 edit"       "$CLI" --weights "$W" --edit-image inputs/fill-stopsign.png --width 1024 --height 1024 --steps 8 --cfg 1.0 --seed 7 --prompt "$P" --out out/warmup_1024.npy
run "int4 1024 edit"              "$CLI" --weights "$W" --edit-image inputs/fill-stopsign.png --width 1024 --height 1024 --steps 8 --cfg 1.0 --seed 7 --prompt "$P" --out out/edit_1024.npy
run "int4 768 edit"               "$CLI" --weights "$W" --edit-image inputs/fill768-stopsign.png --width 768 --height 768 --steps 8 --cfg 1.0 --seed 7 --prompt "$P" --out out/edit_768.npy
run "int4 2048 edit"              "$CLI" --weights "$W" --edit-image inputs/fill-stopsign.png --width 2048 --height 2048 --steps 8 --cfg 1.0 --seed 7 --prompt "$P" --out out/edit_2048.npy
run "int4 1024 t2i"               "$CLI" --weights "$W" --prompt "$T2I" --width 1024 --height 1024 --steps 8 --cfg 1.0 --seed 7 --out out/t2i_1024.npy
run "int4 2048 t2i"               "$CLI" --weights "$W" --prompt "$T2I" --width 2048 --height 2048 --steps 8 --cfg 1.0 --seed 7 --out out/t2i_2048.npy
run "int4 1024 edit limit 12116"  "$CLI" --weights "$W" --edit-image inputs/fill-stopsign.png --width 1024 --height 1024 --steps 8 --cfg 1.0 --seed 7 --prompt "$P" --mlx-limit-mb 12116 --out out/edit_1024_limit12116.npy
run "int4 1024 edit repeat"       "$CLI" --weights "$W" --edit-image inputs/fill-stopsign.png --width 1024 --height 1024 --steps 8 --cfg 1.0 --seed 7 --prompt "$P" --out out/edit_1024_b.npy
echo "=== DONE $(date)" | tee -a "$LOG"
