import numpy as np
from PIL import Image, ImageOps
src = "/Volumes/Satechi/Development/mlxengine-image/corpus/commons-sr/images/exteriors/24e4d6d7a1_Agropoli_02.jpg"
im = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
W, H = im.size
MAG = (255, 0, 255)
# 1024² centre crop, downscaled first so the crop covers most of the scene
s = im.resize((int(W * 1024 / H), 1024), Image.LANCZOS)
sq = s.crop(((s.width - 1024) // 2, 0, (s.width - 1024) // 2 + 1024, 1024))
sq.save("sq.png")
# non-square 1536x1024
ns = im.resize((1536, 1024), Image.LANCZOS)
ns.save("ns.png")
def paint(img, box, name):
    a = np.array(img).copy(); x0, y0, x1, y1 = box
    a[y0:y1, x0:x1] = MAG
    Image.fromarray(a).save(name + ".png")
    m = np.zeros(a.shape[:2], np.uint8); m[y0:y1, x0:x1] = 255
    Image.fromarray(m).save(name + "_mask.png")
# fill regions: lower-middle of the square, right-third of the non-square
paint(sq, (352, 560, 672, 880), "sq_fill")
paint(ns, (980, 540, 1340, 900), "ns_fill")
# expand: 256 px magenta band on the right of the square -> 1280x1024
a = np.full((1024, 1280, 3), MAG, np.uint8); a[:, :1024] = np.array(sq)
Image.fromarray(a).save("sq_expand.png")
m = np.zeros((1024, 1280), np.uint8); m[:, 1024:] = 255
Image.fromarray(m).save("sq_expand_mask.png")
print("ok", sq.size, ns.size)
