"""npy -> png, plus marker/dark check inside the mask and drift outside it (engine's paintingProblem thresholds)."""
import sys, numpy as np
from PIL import Image
def load(p):
    a = np.squeeze(np.load(p).astype(np.float32))
    if a.ndim == 3 and a.shape[0] in (3, 4) and a.shape[-1] not in (3, 4): a = a.transpose(1, 2, 0)
    a = a[..., :3]
    if a.min() < -0.01: a = a * 0.5 + 0.5
    return np.clip(a, 0, 1)
npy, orig, mask = sys.argv[1:4]
out = (load(npy) * 255 + 0.5).astype(np.uint8)
o = np.array(Image.open(orig).convert("RGB")); m = np.array(Image.open(mask).convert("L")) > 127
if out.shape[:2] != o.shape[:2]:
    print("size mismatch", out.shape, o.shape); out = np.array(Image.fromarray(out).resize((o.shape[1], o.shape[0]), Image.LANCZOS))
Image.fromarray(out).save(npy.replace(".npy", ".png"))
r, g, b = [out[..., i].astype(int) for i in range(3)]
purple = ((r - g > 40) & (b - g > 40) & m).sum() / m.sum()
luma = lambda x: 0.2126 * x[..., 0] + 0.7152 * x[..., 1] + 0.0722 * x[..., 2]
lin, lout = luma(out.astype(float))[m].mean(), luma(o.astype(float))[~m].mean()
diff = np.abs(out.astype(float) - o.astype(float)).mean(-1)
drift = diff[~m].mean(); inside = diff[m].mean()
mse = ((out.astype(float) - o.astype(float)) ** 2)[~m].mean(); psnr = 10 * np.log10(255**2 / max(mse, 1e-6))
# composite through the mask, as the engine does
comp = o.copy(); comp[m] = out[m]; Image.fromarray(comp).save(npy.replace(".npy", "_comp.png"))
print(f"{npy}: purple-in-mask {purple*100:.1f}%  luma in/out {lin:.0f}/{lout:.0f}  change inside {inside:.1f}  drift outside {drift:.2f} MAE / {psnr:.1f} dB")
