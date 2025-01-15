import AVFoundation
import UIKit

public class CameraView: UIView {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var captureButton: UIButton!
    private var onImageCaptured: ((UIImage) -> Void)?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
        setupUI()
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let captureSession = captureSession,
              let backCamera = AVCaptureDevice.default(for: .video) else {
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            photoOutput = AVCapturePhotoOutput()
            
            if captureSession.canAddInput(input) &&
               captureSession.canAddOutput(photoOutput!) {
                captureSession.addInput(input)
                captureSession.addOutput(photoOutput!)
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer!)
            
            DispatchQueue.global(qos: .background).async {
                captureSession.startRunning()
            }
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
        }
    }
    
    private func setupUI() {
        // Setup capture button
        captureButton = UIButton(frame: CGRect(x: 0, y: 0, width: 70, height: 70))
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        addSubview(captureButton)
        
        // Add overlay (crosshair or grid)
        let overlayView = createOverlay()
        addSubview(overlayView)
    }
    
    private func createOverlay() -> UIView {
        let overlayView = UIView(frame: bounds)
        overlayView.backgroundColor = .clear
        
        // Add grid lines
        let lineColor = UIColor.white.withAlphaComponent(0.5)
        let lineWidth: CGFloat = 1
        
        // Vertical lines
        for i in 1...2 {
            let x = bounds.width * CGFloat(i) / 3
            let verticalLine = UIView(frame: CGRect(x: x, y: 0, width: lineWidth, height: bounds.height))
            verticalLine.backgroundColor = lineColor
            overlayView.addSubview(verticalLine)
        }
        
        // Horizontal lines
        for i in 1...2 {
            let y = bounds.height * CGFloat(i) / 3
            let horizontalLine = UIView(frame: CGRect(x: 0, y: y, width: bounds.width, height: lineWidth))
            horizontalLine.backgroundColor = lineColor
            overlayView.addSubview(horizontalLine)
        }
        
        return overlayView
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        captureButton.center = CGPoint(x: bounds.midX, y: bounds.maxY - 100)
    }
    
    @objc private func captureButtonTapped() {
        guard let photoOutput = photoOutput else { return }
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private func showConfirmationDialog(with image: UIImage) {
        let alertController = UIAlertController(title: "Photo Captured",
                                              message: "Would you like to keep this photo?",
                                              preferredStyle: .alert)
        
        let saveAction = UIAlertAction(title: "✓", style: .default) { [weak self] _ in
            self?.saveImage(image)
        }
        
        let retakeAction = UIAlertAction(title: "✗", style: .destructive) { _ in
            // Photo will be discarded automatically
        }
        
        alertController.addAction(saveAction)
        alertController.addAction(retakeAction)
        
        if let topViewController = UIApplication.shared.keyWindow?.rootViewController {
            topViewController.present(alertController, animated: true)
        }
    }
    
    private func saveImage(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}

