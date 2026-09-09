import MetalKit
import SwiftUI

// The atmosphere renderer and its offscreen audit use this exact, 16-byte-aligned ABI.
struct SunriseUniforms {
    var viewport: SIMD4<Float> // width, height, sun x, sun y (points)
    var story: SIMD4<Float> // progress, horizon y, sun radius, cloud time
    var optics: SIMD4<Float> = .zero // solar elevation, exposure, paper spread, paper amount
}

#if os(iOS)
/// A single opaque surface owns every sky pixel, including the safe areas.
struct SunriseSkyView: UIViewRepresentable {
    let uniforms: SunriseUniforms

    func makeCoordinator() -> SunriseRenderer { SunriseRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        view.isOpaque = true
        view.backgroundColor = UIColor(red: 10 / 255, green: 17 / 255, blue: 36 / 255, alpha: 1)
        view.clearColor = MTLClearColor(red: 0.039, green: 0.067, blue: 0.141, alpha: 1)
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.autoResizeDrawable = false
        view.isUserInteractionEnabled = false
        view.delegate = context.coordinator
        context.coordinator.uniforms = uniforms
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.uniforms = uniforms
        // The atmosphere has no fine image detail; paper grain is applied at native
        // resolution by SwiftUI. Cap this costly pass independently of wave drawing.
        let scale = min(1, 720 / max(CGFloat(uniforms.viewport.x), CGFloat(uniforms.viewport.y)))
        let size = CGSize(width: max(1, (CGFloat(uniforms.viewport.x) * scale).rounded()),
                          height: max(1, (CGFloat(uniforms.viewport.y) * scale).rounded()))
        if view.drawableSize != size { view.drawableSize = size }
        view.setNeedsDisplay()
    }
}

@MainActor
final class SunriseRenderer: NSObject, MTKViewDelegate {
    let device = MTLCreateSystemDefaultDevice()
    var uniforms = SunriseUniforms(viewport: .zero, story: .zero)
    private var queue: (any MTLCommandQueue)?
    private var pipeline: (any MTLRenderPipelineState)?
    private var transmittance: (any MTLTexture)?
    private var paperGrain: (any MTLTexture)?
    private var lastRendered: SunriseUniforms?

    override init() {
        super.init()
        guard let device, let library = device.makeDefaultLibrary() else { return }
        do {
            queue = device.makeCommandQueue()
            if let image = UIImage(named: "NeutralPaperGrainV1") {
                // The source is a one-channel grayscale PNG. Metal's image loader
                // requires a supported RGB layout; expand once without recoloring it.
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                format.preferredRange = .standard
                let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                let rgba = renderer.image { _ in image.draw(at: .zero) }
                if let cgImage = rgba.cgImage {
                    paperGrain = try MTKTextureLoader(device: device).newTexture(
                        cgImage: cgImage, options: [.SRGB: false])
                }
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "sunriseVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "sunriseFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let texture = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: 256, height: 64, mipmapped: false)
            texture.usage = [.shaderRead, .shaderWrite]
            transmittance = device.makeTexture(descriptor: texture)
            guard let function = library.makeFunction(name: "sunriseTransmittance") else { return }
            let compute = try device.makeComputePipelineState(function: function)
            if let command = queue?.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(compute)
                encoder.setTexture(transmittance, index: 0)
                encoder.dispatchThreads(MTLSize(width: 256, height: 64, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
                encoder.endEncoding()
                command.commit()
            }
        } catch {
            // Keep the ink clear color if Metal compilation fails; never show an
            // unrelated fallback sunrise with different coordinates or timing.
            print("Sunrise renderer unavailable: \(error)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { lastRendered = nil }

    func draw(in view: MTKView) {
        guard uniforms.viewport.x > 0, uniforms.viewport.y > 0 else { return }
        if let lastRendered,
           lastRendered.viewport == uniforms.viewport,
           lastRendered.story == uniforms.story,
           lastRendered.optics == uniforms.optics { return }
        guard let pipeline, let transmittance, let paperGrain,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue?.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SunriseUniforms>.stride, index: 0)
        encoder.setFragmentTexture(transmittance, index: 0)
        encoder.setFragmentTexture(paperGrain, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
        lastRendered = uniforms
    }
}
#endif
