// The pixel head (fm_modules.fm_head / ConvDecoder) at the production 1024² token grid (32×32),
// bf16 as production runs it, on each conv route vs an fp32 CPU reference that uses the SAME
// bf16-rounded weights and input (so only compute error is measured). The component fixture
// (conv_decoder_in, a 4×6 grid) sits below mlx's Winograd window and cannot see this.
//
// Run: SENSENOVA_PARITY=1 swift test -c release -Xswiftc -enable-testing --filter FMHeadGPULaneTests
// (weights: SENSENOVA_WEIGHTS, default <mlxengine-image>/weights/SenseNova-U1.5-8B-MoT)

import Foundation
import MLX
import MLXNN
import MLXRandom
import XCTest

@testable import SenseNovaU1

final class FMHeadGPULaneTests: XCTestCase {
    static func stats(_ a: MLXArray, _ ref: MLXArray) -> String {
        let d = a.asType(.float32) - ref.asType(.float32)
        let rel = sqrt(sum(d * d)) / sqrt(sum(square(ref.asType(.float32))))
        let mx = abs(d).max()
        eval(rel, mx)
        return String(format: "relL2 %.2e  maxAbs %.2e", rel.item(Float.self), mx.item(Float.self))
    }

    func testFMHead1024() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SENSENOVA_PARITY"] == "1", "set SENSENOVA_PARITY=1")
        let store = try ComponentParityTests.ShardStore(ComponentParityTests.weightsDir)
        let w = try store.module("fm_modules.fm_head")
        let w16 = w.mapValues { $0.asType(.bfloat16) }
        let head16 = ConvDecoder(inputDim: 4096)
        try head16.update(parameters: ModuleParameters.unflattened(w16), verify: [.all])
        let head32 = ConvDecoder(inputDim: 4096)
        try head32.update(
            parameters: ModuleParameters.unflattened(w16.mapValues { $0.asType(.float32) }), verify: [.all])
        MLXRandom.seed(0)
        let x16 = MLXRandom.normal([1, 32, 32, 4096]).asType(.bfloat16)  // fixture-scale (std ≈ 1)
        eval(x16)
        let ref = Device.withDefaultDevice(.cpu) { () -> MLXArray in
            let r = head32(x16.asType(.float32))
            eval(r)
            return r
        }
        Memory.clearCache()
        print("[fm_head, 32×32 token grid (1024² image), bf16, vs fp32 CPU on the same inputs]")
        for route in [SenseNovaConvRoute.winograd, .fp32Winograd, .conv3d] {
            head16.convRoute = route
            var out = head16(x16)
            eval(out)
            let t0 = Date()
            for _ in 0..<10 { out = head16(x16); eval(out) }
            let ms = Date().timeIntervalSince(t0) / 10 * 1000
            print(String(format: "  %-13@ %@  %.2f ms/call", route.rawValue, Self.stats(out, ref), ms))
        }
    }
}
