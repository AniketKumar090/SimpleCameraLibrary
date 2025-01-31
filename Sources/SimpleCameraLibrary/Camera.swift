import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#endif

// MARK: - Simplified API Response Models
struct OpenFoodFactsResponse: Codable {
    let product: OpenFoodFactsProduct?
    let status: Int?
    let status_verbose: String?
}

struct OpenFoodFactsProduct: Codable {
    let product_name: String?
    let quantity: String? // Likely contains volume information
    let image_url: String?
}
// MARK: - Product Information Model
public struct ProductInfo: Codable, Identifiable {
    public let id: String // Barcode as unique identifier
    public let name: String
    public let volume: String // Volume as a string (e.g., "500ml")
    public let imageUrl: String?
}

// MARK: - Barcode Scanning and Product Service
@available(iOS 13.0, macOS 13.0, *)
public class ProductScannerService: NSObject, ObservableObject {
    @Published public var session = AVCaptureSession()
    @Published public var metadataOutput = AVCaptureMetadataOutput()
    @Published public var preview: AVCaptureVideoPreviewLayer?
    @Published public var scannedBarcode: String?
    @Published public var productInfo: ProductInfo?
    @Published public var showingScanResult = false
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    
    // UserDefaults key for storing product information
    private let userDefaultsProductInfoKey = "SavedProductInformation"
    
    // Cached product information from UserDefaults
    private var cachedProductInfo: [String: ProductInfo] = [:]
    
    public override init() {
        super.init()
        loadCachedProductInfo()
        checkPermissions()
        setupBarcodeScanner()
    }
    
    // MARK: - UserDefaults Management
    private func loadCachedProductInfo() {
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsProductInfoKey),
           let savedProducts = try? JSONDecoder().decode([String: ProductInfo].self, from: savedData) {
            cachedProductInfo = savedProducts
        }
    }
    
    private func saveProductInfo(_ product: ProductInfo) {
        cachedProductInfo[product.id] = product
        
        if let encoded = try? JSONEncoder().encode(cachedProductInfo) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsProductInfoKey)
        }
    }
    
    // MARK: - Open Food Facts Product Lookup
    public func lookupProductInformation(barcode: String) {
        // First, check if we have a cached result
        if let cachedProduct = cachedProductInfo[barcode] {
            DispatchQueue.main.async {
                self.productInfo = cachedProduct
                self.showingScanResult = true
            }
            return
        }
        
        // If not cached, make an API call
        isLoading = true
        errorMessage = nil
        
        // Open Food Facts API Endpoint
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else {
            handleError("Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.handleError(error.localizedDescription)
                    return
                }
                
                guard let data = data else {
                    self.handleError("No product data received")
                    return
                }
                
                do {
                    let apiResponse = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
                    
                    // Validate response and product
                    guard let product = apiResponse.product else {
                        self.handleError("No product found")
                        return
                    }
                    
                    // Extract volume from the quantity field
                    let volume = self.extractVolume(from: product.quantity) ?? "Unknown Volume"
                    
                    // Convert Open Food Facts product to our ProductInfo
                    let productInfo = ProductInfo(
                        id: barcode,
                        name: product.product_name ?? "Unknown Product",
                        volume: volume,
                        imageUrl: product.image_url
                    )
                    
                    self.productInfo = productInfo
                    self.saveProductInfo(productInfo)
                    self.showingScanResult = true
                } catch {
                    self.handleError("Failed to decode product information: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    // Helper method to extract volume from quantity string
    private func extractVolume(from quantityString: String?) -> String? {
        guard let quantity = quantityString else { return nil }
        
        // Extract numeric value followed by ml, cl, L, etc.
        let volumeRegex = try? NSRegularExpression(pattern: "(\\d+)\\s*(ml|cl|L|liters?|g|kg)", options: .caseInsensitive)
        let range = NSRange(location: 0, length: quantity.utf16.count)
        
        if let match = volumeRegex?.firstMatch(in: quantity, options: [], range: range) {
            // Safely extract the captured group
            let matchRange = match.range(at: 0)
            
            if matchRange.location != NSNotFound,
               let matchedRange = Range(matchRange, in: quantity) {
                return String(quantity[matchedRange])
            }
        }
        
        return nil
    }
    
    private func handleError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showingScanResult = true
        }
    }

    
    // MARK: - Camera Permissions
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupBarcodeScanner()
                    }
                }
            }
        default:
            return
        }
    }
    
    // MARK: - Barcode Scanner Setup
    private func setupBarcodeScanner() {
        do {
            session.beginConfiguration()
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: .back) else { return }
            
            let input = try AVCaptureDeviceInput(device: device)
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                
                // Set barcode types you want to scan
                metadataOutput.metadataObjectTypes = [
                    .ean8,
                    .ean13,
                    .qr,
                    .code128,
                    .code39,
                    .code93,
                    .upce
                ]
            }
            
            session.commitConfiguration()
        } catch {
            print("Error setting up barcode scanner: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Scanning Control
    public func startScanning() {
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    public func stopScanning() {
        DispatchQueue.global(qos: .background).async {
            self.session.stopRunning()
        }
    }
}

// MARK: - Metadata Capture Delegate
@available(iOS 13.0, macOS 13.0, *)
extension ProductScannerService: AVCaptureMetadataOutputObjectsDelegate {
    public func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject {
            let barcode = metadataObject.stringValue ?? ""
            
            DispatchQueue.main.async {
                self.scannedBarcode = barcode
                self.lookupProductInformation(barcode: barcode)
                self.stopScanning()
            }
        }
    }
}

// MARK: - Barcode Scanner Preview View (Platform-Specific)
#if os(iOS)
@available(iOS 13.0, *)
public struct BarcodeScannerPreviewView: UIViewRepresentable {
    @ObservedObject var scannerService: ProductScannerService
    public init(scannerService: ProductScannerService) {
        self.scannerService = scannerService
    }
        
    public func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        scannerService.preview = AVCaptureVideoPreviewLayer(session: scannerService.session)
        scannerService.preview?.frame = view.frame
        scannerService.preview?.videoGravity = .resizeAspectFill
        
        view.layer.addSublayer(scannerService.preview!)
        scannerService.startScanning()
        
        return view
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {}
}
#elseif os(macOS)
@available(macOS 13.0, *)
public struct BarcodeScannerPreviewView: NSViewRepresentable {
    @ObservedObject var scannerService: ProductScannerService
    public init(scannerService: ProductScannerService) {
        self.scannerService = scannerService
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        
        scannerService.preview = AVCaptureVideoPreviewLayer(session: scannerService.session)
        scannerService.preview?.frame = view.frame
        scannerService.preview?.videoGravity = .resizeAspectFill
        
        view.layer = scannerService.preview
        scannerService.startScanning()
        
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

