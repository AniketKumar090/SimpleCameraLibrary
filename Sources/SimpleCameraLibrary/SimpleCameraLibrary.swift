// The Swift Programming Language
// https://docs.swift.org/swift-book
extension CameraView: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput,
                          didFinishProcessingPhoto photo: AVCapturePhoto,
                          error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.showConfirmationDialog(with: image)
        }
    }
}
