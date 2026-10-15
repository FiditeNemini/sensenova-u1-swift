// npy2png: float .npy (HWC or CHW, [-1,1] or [0,1]) -> PNG, printing value stats and NaN/inf counts.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let argv = CommandLine.arguments
guard argv.count >= 3 else { print("usage: npy2png in.npy out.png"); exit(2) }
guard let raw = FileManager.default.contents(atPath: argv[1]) else { print("cannot read \(argv[1])"); exit(1) }
guard raw.count > 12, raw[0] == 0x93, raw[1] == 0x4E else { print("not an npy file"); exit(1) }
let major = Int(raw[6])
let hlen: Int, hoff: Int
if major == 1 { hlen = Int(raw[8]) | Int(raw[9]) << 8; hoff = 10 }
else { hlen = Int(raw[8]) | Int(raw[9]) << 8 | Int(raw[10]) << 16 | Int(raw[11]) << 24; hoff = 12 }
let header = String(decoding: raw[hoff..<(hoff + hlen)], as: UTF8.self)
func capture(_ pattern: String) -> String? {
    let re = try! NSRegularExpression(pattern: pattern)
    let ns = header as NSString
    guard let m = re.firstMatch(in: header, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return ns.substring(with: m.range(at: 1))
}
let descr = capture("'descr':\\s*'([^']+)'") ?? "<f4"
let fortran = (capture("'fortran_order':\\s*(True|False)") ?? "False") == "True"
var shape = (capture("'shape':\\s*\\(([^)]*)\\)") ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
if fortran { print("fortran_order unsupported"); exit(1) }
let body = Data(raw[(hoff + hlen)...])
var vals: [Float]
switch descr {
case "<f4": vals = body.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
case "<f2": vals = body.withUnsafeBytes { $0.bindMemory(to: Float16.self).map { Float($0) } }
case "<f8": vals = body.withUnsafeBytes { $0.bindMemory(to: Double.self).map { Float($0) } }
default: print("unsupported dtype \(descr)"); exit(1)
}
shape = shape.filter { $0 != 1 }
guard shape.count == 3 else { print("unexpected shape \(shape)"); exit(1) }
var h = shape[0], w = shape[1], c = shape[2]
var hwc = vals
if (shape[0] == 3 || shape[0] == 4) && !(shape[2] == 3 || shape[2] == 4) {
    c = shape[0]; h = shape[1]; w = shape[2]
    hwc = [Float](repeating: 0, count: h * w * c)
    for ch in 0..<c { for y in 0..<h { for x in 0..<w { hwc[(y * w + x) * c + ch] = vals[(ch * h + y) * w + x] } } }
}
guard hwc.count == h * w * c else { print("size mismatch: \(hwc.count) vs \(h)x\(w)x\(c)"); exit(1) }
var mn = Float.greatestFiniteMagnitude, mx = -Float.greatestFiniteMagnitude, sum = 0.0, bad = 0
for v in hwc { if v.isNaN || v.isInfinite { bad += 1; continue }; mn = min(mn, v); mx = max(mx, v); sum += Double(v) }
let mean = sum / Double(max(hwc.count - bad, 1))
let normalized = mn < -0.01
var px = [UInt8](repeating: 255, count: h * w * 4)
for i in 0..<(h * w) {
    for k in 0..<3 {
        var v = hwc[i * c + k]
        if !v.isFinite { v = 0 }
        if normalized { v = v * 0.5 + 0.5 }
        px[i * 4 + k] = UInt8(max(0, min(255, (v * 255 + 0.5).rounded(.down))))
    }
}
let ok: Bool = px.withUnsafeMutableBytes { buf -> Bool in
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: argv[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(dest, img, nil)
    return CGImageDestinationFinalize(dest)
}
guard ok else { print("png write failed"); exit(1) }
let f = { (x: Float) in String(format: "%.4f", x) }
print("\(argv[1]): \(w)x\(h)x\(c) \(descr) min \(f(mn)) max \(f(mx)) mean \(String(format: "%.4f", mean)) nan/inf \(bad) \(normalized ? "[-1,1]->[0,1]" : "[0,1]") -> \(argv[2])")
