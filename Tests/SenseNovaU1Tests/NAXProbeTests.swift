// NAXProbeTests.swift — regression guard for the NAX split-K GEMM bug (mlx#3797, fixed
// upstream by #3810, first shipped to Swift in mlx-swift 0.32.2).
//
// On mlx-swift ≤0.31.6 with MLX_METAL_JIT=ON, a half-precision matmul in the window
//   M·N ≥ 2048² , K ≥ 10240 , K ≥ 3·max(M,N)
// was mis-instantiated with the output dtype and returned garbage/NaN on M5-class GPUs.
//
// In this model that window is exactly the LLM FFN down-projection: K = intermediateSize
// = 12288, N = hiddenSize = 4096, so 1024 ≤ M ≤ 4096 tokens qualify — a 1024² denoise
// (1024 tokens) produced 100% NaN. `MoTMLP` used to row-chunk at ≤896 to dodge it; the
// chunk was removed once this probe passed edge-to-edge on 0.32.2 and the manifest floor
// was raised to 0.32.2 so no consumer can resolve back into the broken range.
//
// Weights-free (seeded LCG), runs on every test pass. If this ever fails, the fix has
// regressed: restore the row-chunk in `MoTMLP.callAsFunction` before shipping.

import Foundation
import MLX
import XCTest

final class NAXProbeTests: XCTestCase {

    private static func lcgArray(_ shape: [Int], seed: UInt64 = 0x9E37_79B9_7F4A_7C15)
        -> MLXArray
    {
        var lcg = seed
        let n = shape.reduce(1, *)
        let v = (0..<n).map { _ -> Float in
            lcg = lcg &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: lcg >> 11)) / Float(Int64.max >> 11)
        }
        return MLXArray(v, shape)
    }

    private static func cosine(_ a: MLXArray, _ b: MLXArray) -> Float {
        let x = a.asType(.float32).flattened()
        let y = b.asType(.float32).flattened()
        let c = sum(x * y) / (sqrt(sum(x * x)) * sqrt(sum(y * y)) + 1e-12)
        eval(c)
        return c.item(Float.self)
    }

    /// Raw bf16 GEMM at the FFN down-projection shape, across the dispatch window.
    func testFeedForwardDownProjectionGEMMWindow() throws {
        let (K, N) = (12288, 4096)
        let b = Self.lcgArray([N, K]).asType(.bfloat16)
        // 896 = the old chunk size (below the window); 1024 = first qualifying M
        // (M·N = 2048² exactly); 2048 mid-window; 4096 = last qualifying M (K ≥ 3·M
        // fails at 4097); 8192 above the window.
        for m in [896, 1024, 2048, 4096, 8192] {
            let a = Self.lcgArray([m, K], seed: UInt64(m) &* 2_654_435_761).asType(.bfloat16)
            let y = matmul(a, b.T)
            let ref = matmul(a.asType(.float32), b.asType(.float32).T)
            eval(y, ref)
            let cos = Self.cosine(y, ref)
            let maxAbs = abs(y.asType(.float32) - ref).max().item(Float.self)
            print(String(format: "  M=%d K=%d N=%d bf16: cos %.8f max_abs %.3e", m, K, N, cos, maxAbs))
            // STRICT on purpose: corruption just past the boundary can read cos ~0.998,
            // which a loose ≥0.99 check passes while still being garbage.
            XCTAssertGreaterThan(cos, 0.999, "M=\(m): NAX split-K corruption (mlx#3797)")
            XCTAssertTrue(maxAbs.isFinite && maxAbs < 100, "M=\(m): max_abs \(maxAbs)")
        }
    }
}
