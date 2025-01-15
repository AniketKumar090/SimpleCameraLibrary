import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

// MARK: - Camera Service
@available(iOS 13.0, macOS 10.15, *)
public class CameraService: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var output = AVCapturePhotoOutput()
    @Published var preview: AVCaptureVideoPreviewLayer?
    @Published var recentImage: PlatformImage?
    @Published var showingPhotoReview = false
    
    override public init() {
        super.init()
        checkPermissions()
        setupCamera()
    }
    
    public func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupCamera()
                    }
                }
            }
        default:
            return
        }
    }
    
    public func setupCamera() {
        do {
            session.beginConfiguration()
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: .back) else { return }
            
            let input = try AVCaptureDeviceInput(device: device)
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.commitConfiguration()
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
        }
    }
    
    public func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - Photo Capture Delegate
@available(iOS 13.0, macOS 10.15, *)
extension CameraService: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput,
                    didFinishProcessingPhoto photo: AVCapturePhoto,
                    error: Error?) {
        if let imageData = photo.fileDataRepresentation() {
            #if os(iOS)
            if let image = UIImage(data: imageData) {
                DispatchQueue.main.async {
                    self.recentImage = image
                    self.showingPhotoReview = true
                }
            }
            #elseif os(macOS)
            if let image = NSImage(data: imageData) {
                DispatchQueue.main.async {
                    self.recentImage = image
                    self.showingPhotoReview = true
                }
            }
            #endif
        }
    }
}

// MARK: - Camera Preview View
#if os(iOS)
@available(iOS 13.0, *)
public struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraService: CameraService
    
    public func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        cameraService.preview = AVCaptureVideoPreviewLayer(session: cameraService.session)
        cameraService.preview?.frame = view.frame
        cameraService.preview?.videoGravity = .resizeAspectFill
        
        view.layer.addSublayer(cameraService.preview!)
        cameraService.session.startRunning()
        
        return view
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {}
}
#elseif os(macOS)
@available(macOS 10.15, *)
public struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var cameraService: CameraService
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        
        cameraService.preview = AVCaptureVideoPreviewLayer(session: cameraService.session)
        cameraService.preview?.frame = view.frame
        cameraService.preview?.videoGravity = .resizeAspectFill
        
        view.layer = cameraService.preview
        cameraService.session.startRunning()
        
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

// MARK: - Camera View
@available(iOS 14.0, macOS 11.0, *)
public struct CameraView: View {
    @StateObject private var cameraService = CameraService()
    
    public var body: some View {
        ZStack {
            CameraPreviewView(cameraService: cameraService)
            
            VStack {
                Spacer()
                
                Button(action: {
                    cameraService.capturePhoto()
                }) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.black, lineWidth: 2)
                        )
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $cameraService.showingPhotoReview) {
            if let image = cameraService.recentImage {
                PhotoReviewView(image: image, isPresented: $cameraService.showingPhotoReview)
            }
        }
    }
}

// MARK: - Photo Review View
@available(iOS 13.0, macOS 11.0, *)
public struct PhotoReviewView: View {
    let image: PlatformImage
    @Binding var isPresented: Bool
    
    public var body: some View {
        VStack {
            #if os(iOS)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
            #elseif os(macOS)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
            #endif
            
            HStack(spacing: 50) {
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.red)
                }
                
                Button(action: {
                    #if os(iOS)
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    #elseif os(macOS)
                    // Implement macOS photo saving logic here
                    let savePanel = NSSavePanel()
                    savePanel.allowedContentTypes = [.jpeg, .png]
                    savePanel.canCreateDirectories = true
                    savePanel.isExtensionHidden = false
                    savePanel.title = "Save Photo"
                    savePanel.message = "Choose a location to save your photo"
                    savePanel.nameFieldLabel = "Photo Name:"
                    
                    if let window = NSApp.windows.first {
                        savePanel.beginSheetModal(for: window) { response in
                            if response == .OK {
                                if let url = savePanel.url,
                                   let imageData = image.tiffRepresentation,
                                   let bitmap = NSBitmapImageRep(data: imageData),
                                   let data = bitmap.representation(using: .jpeg, properties: [:]) {
                                    try? data.write(to: url)
                                }
                            }
                        }
                    }
                    #endif
                    isPresented = false
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.green)
                }
            }
            .padding(.bottom, 30)
        }
    }
}
