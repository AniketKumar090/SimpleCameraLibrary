import AVFoundation
import UIKit

public class CameraView: UIView {
    private var captureSession: AVCaptureSession!
    private var photoOutput: AVCapturePhotoOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    
    public var capturedImage: UIImage?
    
    // Capture button closure
    public var onCapture: ((UIImage) -> Void)?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        // Set up camera input
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else { return }
        
        captureSession.addInput(videoDeviceInput)
        
        // Set up photo output
        photoOutput = AVCapturePhotoOutput()
        guard captureSession.canAddOutput(photoOutput) else { return }
        captureSession.addOutput(photoOutput)
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = self.bounds
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        
        captureSession.startRunning()
    }
    
    // Capture the photo
    public func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // Setup the overlay and capture button
    public func setupOverlay() {
        let captureButton = UIButton(frame: CGRect(x: self.bounds.midX - 40, y: self.bounds.height - 100, width: 80, height: 80))
        captureButton.layer.cornerRadius = 40
        captureButton.backgroundColor = .systemBlue
        captureButton.setTitle("Capture", for: .normal)
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        self.addSubview(captureButton)
    }
    
    @objc private func captureButtonTapped() {
        capturePhoto()
    }
}

extension CameraView: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput,
                            didFinishProcessingPhoto photo: AVCapturePhoto,
                            error: Error?) {
        guard let photoData = photo.fileDataRepresentation(),
              let image = UIImage(data: photoData) else { return }
        
        // Display the photo for user confirmation
        capturedImage = image
        // Call the callback if exists
        onCapture?(image)
    }
}
