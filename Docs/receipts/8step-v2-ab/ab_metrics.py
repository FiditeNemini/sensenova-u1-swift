"""V1 vs V2 8-step tier A/B: per-image stats + pairwise cosine + side-by-side PNGs.
Usage: python ab_metrics.py <dir-with-npy> [sheet-outdir]"""
import sys, glob, os, numpy as np
from PIL import Image, ImageFilter

def load(p):
    a = np.load(p).astype(np.float32)
    a = np.squeeze(a)
    if a.ndim == 3 and a.shape[0] in (3, 4) and a.shape[-1] not in (3, 4):
        a = a.transpose(1, 2, 0)           # CHW -> HWC
    a = a[..., :3]
    if a.min() < -0.01:                    # normalized space -> [0,1]
        a = a * 0.5 + 0.5
    return np.clip(a, 0, 1)

def stats(x):
    r, g, b = x[..., 0], x[..., 1], x[..., 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    mx, mn = x.max(-1), x.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    # sharpness / oversharpening proxies on luminance
    lap = (lum[1:-1, 1:-1] * 4 - lum[:-2, 1:-1] - lum[2:, 1:-1] - lum[1:-1, :-2] - lum[1:-1, 2:])
    gx = np.diff(lum, axis=1); gy = np.diff(lum, axis=0)
    grad = np.sqrt(gx[:-1, :] ** 2 + gy[:, :-1] ** 2)
    # high-frequency energy share: energy outside the central 1/4 of the spectrum
    F = np.abs(np.fft.fftshift(np.fft.fft2(lum - lum.mean()))) ** 2
    h, w = F.shape; c = F[h // 4: 3 * h // 4, w // 4: 3 * w // 4].sum()
    hf_share = 1 - c / max(F.sum(), 1e-9)
    return dict(
        R=r.mean(), G=g.mean(), B=b.mean(), lum=lum.mean(),
        rms_contrast=lum.std(), sat=sat.mean(),
        clip_lo=(lum < 0.02).mean(), clip_hi=(lum > 0.98).mean(),
        lap_var=lap.var(), grad_p99=np.percentile(grad, 99), hf_share=hf_share)

def cos(a, b):
    a = a.ravel() - 0.5; b = b.ravel() - 0.5
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))

def to_img(x): return Image.fromarray((x * 255).round().astype(np.uint8))

d = sys.argv[1]; sheets = sys.argv[2] if len(sys.argv) > 2 else None
files = sorted(glob.glob(os.path.join(d, "*.npy")))
imgs = {os.path.basename(f)[:-4]: load(f) for f in files}
keys = ["R", "G", "B", "lum", "rms_contrast", "sat", "clip_lo", "clip_hi", "lap_var", "grad_p99", "hf_share"]
print("name".ljust(32) + " ".join(k.rjust(9) for k in keys))
rows = {}
for n, x in imgs.items():
    s = stats(x); rows[n] = s
    print(n.ljust(32) + " ".join(f"{s[k]:9.4f}" for k in keys))
    if sheets: os.makedirs(sheets, exist_ok=True); to_img(x).save(os.path.join(sheets, n + ".png"))

print("\n== pairwise: V1 vs V2 (same quant), and V2 8bit vs V2 4bit ==")
prompts = sorted({n.split("__", 1)[1] for n in imgs})
agg = {}
for p in prompts:
    for q in ("8bit", "4bit"):
        a, b = f"8step-{q}__{p}", f"8step-v2-{q}__{p}"
        if a in imgs and b in imgs:
            c = cos(imgs[a], imgs[b]); d1, d2 = rows[a], rows[b]
            delta = {k: d2[k] - d1[k] for k in keys}
            agg.setdefault(q, []).append(delta)
            print(f"{p:14s} {q}: cos(V1,V2)={c:.4f}  Δsat={delta['sat']:+.4f} Δcontrast={delta['rms_contrast']:+.4f} "
                  f"Δlum={delta['lum']:+.4f} Δlap_var={delta['lap_var']:+.5f} Δhf={delta['hf_share']:+.4f} Δgrad99={delta['grad_p99']:+.4f}")
            if sheets:
                A, B = to_img(imgs[a]), to_img(imgs[b]); W, H = A.size
                sheet = Image.new("RGB", (W * 2 + 8, H), (255, 255, 255)); sheet.paste(A, (0, 0)); sheet.paste(B, (W + 8, 0))
                sheet.save(os.path.join(sheets, f"AB_{q}_{p}.png"))
    a, b = f"8step-v2-8bit__{p}", f"8step-v2-4bit__{p}"
    if a in imgs and b in imgs: print(f"{p:14s} V2 int8 vs int4: cos={cos(imgs[a], imgs[b]):.4f}")
    a, b = f"8step-8bit__{p}", f"8step-4bit__{p}"
    if a in imgs and b in imgs: print(f"{p:14s} V1 int8 vs int4: cos={cos(imgs[a], imgs[b]):.4f}")
print("\n== mean Δ(V2−V1) over prompts ==")
for q, ds in agg.items():
    print(q, {k: round(float(np.mean([x[k] for x in ds])), 5) for k in ("sat", "rms_contrast", "lum", "lap_var", "hf_share", "grad_p99", "clip_lo", "clip_hi")})
