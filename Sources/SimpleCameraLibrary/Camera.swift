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
    let quantity: String?
    let image_url: String?
    let categories: String?
    let generic_name: String?
    let _keywords: [String]? // Add this field
}

// Update ProductInfo to include drink category string
public struct ProductInfo: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let volume: String
    public let imageUrl: String?
    public let keywords: [String]?
    public let drinkCategory: String? // Add this field
    
    public static func == (lhs: ProductInfo, rhs: ProductInfo) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.volume == rhs.volume &&
               lhs.imageUrl == rhs.imageUrl &&
               lhs.keywords == rhs.keywords &&
               lhs.drinkCategory == rhs.drinkCategory
    }
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
    public func determineDrinkCategory(categories: String?, genericName: String?) -> String? {
        let categories = categories?.lowercased() ?? ""
        let genericName = genericName?.lowercased() ?? ""
        let combinedText = categories + " " + genericName
        
        if combinedText.contains("water") || combinedText.contains("eau") {
            return "water"
        } else if combinedText.contains("tea") || combinedText.contains("thé") {
            return "tea"
        } else if combinedText.contains("coffee") || combinedText.contains("café") {
            return "coffee"
        } else if combinedText.contains("soda") || combinedText.contains("soft drink") {
            return "soda"
        }
        return nil
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
            
            DispatchQueue.main.async { [self] in
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
                    
                    guard let product = apiResponse.product else {
                        self.handleError("No product found")
                        return
                    }
                    
                    // Debug print
                    print("Raw keywords from API: \(product._keywords ?? [])")
                    
                    let volume = self.extractVolume(from: product.quantity) ?? "Unknown Volume"
                    let drinkCategory = self.determineDrinkCategory(
                        categories: product.categories,
                        genericName: product.generic_name
                    )
                    
                    // Use _keywords directly from the API instead of extracting from categories
                    let productInfo = ProductInfo(
                        id: barcode,
                        name: product.product_name ?? "Unknown Product",
                        volume: volume,
                        imageUrl: product.image_url,
                        keywords: product._keywords, // Use the API-provided keywords
                        drinkCategory: drinkCategory
                    )
                    
                    print("Created ProductInfo with keywords: \(productInfo.keywords ?? [])")
                    
                    self.productInfo = productInfo
                    self.saveProductInfo(productInfo)
                    self.showingScanResult = true
                } catch {
                    self.handleError("Failed to decode product information: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    private func extractKeywords(from categories: String?) -> [String]? {
        guard let categories = categories else { return nil }
        
        // Split categories by commas and clean up each keyword
        return categories
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
    
    // Mark the initializer as public
    public init(scannerService: ProductScannerService) {
        self.scannerService = scannerService
    }
    
    public func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        scannerService.preview = AVCaptureVideoPreviewLayer(session: scannerService.session)
        scannerService.preview?.frame = view.bounds
        scannerService.preview?.videoGravity = .resizeAspectFill // Ensure no zoom
        
        // Set the preview layer's orientation to match the device's orientation
        if let connection = scannerService.preview?.connection {
            connection.videoOrientation = .portrait
        }
        
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
    
    // Mark the initializer as public
    public init(scannerService: ProductScannerService) {
        self.scannerService = scannerService
    }
    
    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        
        scannerService.preview = AVCaptureVideoPreviewLayer(session: scannerService.session)
        scannerService.preview?.frame = view.bounds
        scannerService.preview?.videoGravity = .resizeAspect // Ensure no zoom
        
        view.layer = scannerService.preview
        scannerService.startScanning()
        
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
// MARK: - Example Usage in SwiftUI
//@available(iOS 13.0, macOS 13.0, *)
//struct ContentView: View {
//    @StateObject private var scannerService = ProductScannerService()
//    
//    var body: some View {
//        VStack {
//            if scannerService.showingScanResult {
//                if let productInfo = scannerService.productInfo {
//                    Text("Product: \(productInfo.name)")
//                    Text("Volume: \(productInfo.volume)")
//                    if let imageUrl = productInfo.imageUrl, let url = URL(string: imageUrl) {
//                        AsyncImage(url: url) { image in
//                            image.resizable()
//                        } placeholder: {
//                            ProgressView()
//                        }
//                        .frame(width: 100, height: 100)
//                    }
//                } else if let errorMessage = scannerService.errorMessage {
//                    Text("Error: \(errorMessage)")
//                        .foregroundColor(.red)
//                }
//                Button("Scan Again") {
//                    scannerService.showingScanResult = false
//                    scannerService.startScanning()
//                }
//            } else {
//                BarcodeScannerPreviewView(scannerService: scannerService)
//                    .edgesIgnoringSafeArea(.all)
//            }
//        }
//    }
//}
