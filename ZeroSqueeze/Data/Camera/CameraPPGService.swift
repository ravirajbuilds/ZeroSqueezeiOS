import Foundation
import AVFoundation
import CoreVideo
import CoreImage

/// Drives the rear camera + torch and emits per-frame mean-RGB samples.
///
/// Concurrency contract:
///   - The class is `@MainActor` so its `@Published` UI state is safe to read
///     from SwiftUI views without hopping actors.
///   - `AVCaptureSession` calls (`beginConfiguration`, `commitConfiguration`,
///     `startRunning`, `stopRunning`, torch toggles) are blocking and MUST
///     NOT run on the main thread. They are dispatched onto `sessionQueue`.
///     The capture device + outputs are marked `nonisolated(unsafe)` and are
///     only ever touched from `sessionQueue`.
///   - Frame callbacks land on `sampleQueue` (the AVCapture delegate queue).
///     Each frame is averaged synchronously there, then a single `Task
///     @MainActor` hop publishes the sample to consumers.
@MainActor
final class CameraPPGService: NSObject, ObservableObject {

    // ── Published UI state ─────────────────────────────────────────
    @Published private(set) var isRunning = false
    @Published private(set) var fingerCovered = false
    @Published private(set) var latestRed: Double = 0
    @Published private(set) var sessionError: String?

    // ── Configuration ──────────────────────────────────────────────
    nonisolated static let roiSize: CGFloat = 0.4
    nonisolated static let coverageRedThreshold: Double = 180
    nonisolated static let targetFps: Double = 30

    // ── Capture stack (touched only on sessionQueue) ───────────────
    nonisolated(unsafe) private let session = AVCaptureSession()
    /// The live session, for an `AVCaptureVideoPreviewLayer`. The preview layer
    /// only reads the session and may be attached from the main thread safely.
    nonisolated var captureSession: AVCaptureSession { session }
    nonisolated private let sampleQueue = DispatchQueue(label: "zerosqueeze.ppg.samples")
    nonisolated private let sessionQueue = DispatchQueue(label: "zerosqueeze.ppg.session")
    nonisolated(unsafe) private var videoOutput: AVCaptureVideoDataOutput?
    nonisolated(unsafe) private var device: AVCaptureDevice?

    /// Consumer callback. Set before calling `start`.
    var onSample: ((PPGSample) -> Void)?

    /// Incremented on every `stop()` so a partially-completed `start()` can
    /// detect that it was cancelled and refuse to set `isRunning = true`.
    private var generation: Int = 0

    // ── Lifecycle ──────────────────────────────────────────────────

    func start() async {
        guard !isRunning else { return }
        generation &+= 1
        let myGen = generation
        sessionError = nil
        do {
            try await requestCameraPermission()
            guard myGen == generation else { teardownAsync(); return }
            try await configureSessionAsync()
            guard myGen == generation else { teardownAsync(); return }
            await startSessionAsync()
            guard myGen == generation else { teardownAsync(); return }
            try await setTorchAsync(on: true)
            guard myGen == generation else { teardownAsync(); return }
            isRunning = true
        } catch {
            // `setTorchAsync` (or any later throw) can fire after the session is
            // already running — leaving the camera + torch live in the
            // background despite the caller seeing `.failed`. Teardown
            // unconditionally on any error path.
            teardownAsync()
            sessionError = error.localizedDescription
            isRunning = false
            ZSLogger.error(.ppg, "PPG start failed", error: error)
        }
    }

    func stop() {
        // Always bump generation so any in-flight start aborts before
        // flipping isRunning = true.
        generation &+= 1
        isRunning = false
        fingerCovered = false
        latestRed = 0
        teardownAsync()
    }

    /// Idempotent teardown — torch off + stopRunning on `sessionQueue`.
    ///
    /// `device` and `session` are read inside the queue closure, not captured
    /// at call-site, so the read happens on the same queue that writes them
    /// (`configureSessionSync`). Capturing `[device]` on MainActor would race
    /// with a concurrent configure.
    nonisolated private func teardownAsync() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let device = self.device, device.hasTorch {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = .off
                    device.unlockForConfiguration()
                } catch {
                    // Best-effort cleanup.
                }
            }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // ── Permission ─────────────────────────────────────────────────

    private func requestCameraPermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw NSError(domain: "ZeroSqueeze.PPG", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Camera permission denied"
            ])
        }
    }

    // ── Session config on background queue ─────────────────────────

    private func configureSessionAsync() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }
                do {
                    try self.configureSessionSync()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Runs on `sessionQueue`. Touches nonisolated(unsafe) state only.
    nonisolated private func configureSessionSync() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .vga640x480
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "ZeroSqueeze.PPG", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "No back camera available"
            ])
        }
        self.device = device

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "ZeroSqueeze.PPG", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add camera input"
            ])
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "ZeroSqueeze.PPG", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add video output"
            ])
        }
        session.addOutput(output)
        self.videoOutput = output

        try configureDevice(device)
    }

    /// Lock AE/AWB/AF so the PPG signal isn't crushed by camera auto-tuning.
    nonisolated private func configureDevice(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Self.targetFps))
        let supportsTarget = device.activeFormat.videoSupportedFrameRateRanges.contains { range in
            CMTimeGetSeconds(range.minFrameDuration) <= 1.0 / Self.targetFps
        }
        if supportsTarget {
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
        }

        if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
    }

    private func startSessionAsync() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }
                if !self.session.isRunning { self.session.startRunning() }
                cont.resume()
            }
        }
    }

    private func setTorchAsync(on: Bool) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self, let device = self.device, device.hasTorch else { cont.resume(); return }
                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    if on {
                        try device.setTorchModeOn(level: min(0.6, AVCaptureDevice.maxAvailableTorchLevel))
                    } else {
                        device.torchMode = .off
                    }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

// ── Frame processing ───────────────────────────────────────────────

extension CameraPPGService: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        let rgb = Self.meanRGB(in: pixelBuffer, roiFraction: Self.roiSize)
        let sample = PPGSample(t: timestamp, r: rgb.r, g: rgb.g, b: rgb.b)
        let covered = rgb.r >= Self.coverageRedThreshold

        // `captureOutput` is serial (single delegate queue), and
        // `DispatchQueue.main.async` preserves submission order — so samples
        // reach the processor in timestamp order. A per-frame `Task { @MainActor }`
        // would NOT: hops to the main actor have no FIFO guarantee and could
        // reorder samples, corrupting the PPGProcessor's monotonic-time window.
        // `[weak self]` + the `isRunning` gate drop frames already in flight when
        // `stop()` ran, so a stale sample can't mutate a reset VM/processor.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                guard self.isRunning else { return }
                self.latestRed = rgb.r
                self.fingerCovered = covered
                self.onSample?(sample)
            }
        }
    }

    /// Mean BGRA across a centred ROI. Returns components in 0-255 space.
    nonisolated static func meanRGB(in pixelBuffer: CVPixelBuffer, roiFraction: CGFloat) -> (r: Double, g: Double, b: Double) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return (0, 0, 0)
        }
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        let roiW = max(1, Int(CGFloat(width) * roiFraction))
        let roiH = max(1, Int(CGFloat(height) * roiFraction))
        let x0 = (width - roiW) / 2
        let y0 = (height - roiH) / 2

        let stride = max(1, roiW / 32)
        var br: UInt64 = 0
        var bg: UInt64 = 0
        var bb: UInt64 = 0
        var count: UInt64 = 0

        var y = y0
        while y < y0 + roiH {
            var x = x0
            let rowPtr = ptr.advanced(by: y * bytesPerRow)
            while x < x0 + roiW {
                let p = rowPtr.advanced(by: x * 4)
                // BGRA layout
                bb &+= UInt64(p[0])
                bg &+= UInt64(p[1])
                br &+= UInt64(p[2])
                count &+= 1
                x += stride
            }
            y += stride
        }
        guard count > 0 else { return (0, 0, 0) }
        return (Double(br) / Double(count), Double(bg) / Double(count), Double(bb) / Double(count))
    }
}
