import SwiftUI
import UIKit
import AVFoundation

/// A live `AVCaptureVideoPreviewLayer` bridged into SwiftUI.
///
/// Used by both capture flows so the user can actually see what the camera
/// sees — essential for the chest scan (centring a scg you can't see is
/// impossible) and reassuring for the fingertip scan (the lit red field
/// confirms the lens is covered).
///
/// The session is owned and driven by `CameraPPGService`;
/// this view only attaches a preview layer to it. Reading the session and
/// attaching a preview layer from the main thread is safe.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Mirror horizontally — set for the front (selfie) camera so the preview
    /// matches what a mirror would show.
    var mirrored: Bool = false

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        configure(view.videoPreviewLayer.connection)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        configure(uiView.videoPreviewLayer.connection)
    }

    private func configure(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        // Portrait. iOS 17+ expresses orientation as a rotation angle.
        let portrait: CGFloat = 90
        if connection.isVideoRotationAngleSupported(portrait) {
            connection.videoRotationAngle = portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
    }

    /// A `UIView` whose backing layer IS the preview layer, so it resizes with
    /// the view automatically (no manual frame bookkeeping).
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
