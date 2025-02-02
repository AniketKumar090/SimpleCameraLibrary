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
    let _keywords: [String]? // Make sure this matches the API response exactly
    let serving_size: String? // Add this field to capture serving size
    
    private enum CodingKeys: String, CodingKey {
        case product_name
        case quantity
        case image_url
        case categories
        case generic_name
        case _keywords = "_keywords"
        case serving_size // Map to the "serving_size" field in the API response
    }
}
// Update ProductInfo to include drink category string
public struct ProductInfo: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let volume: String
    public let imageUrl: String?
    public let keywords: [String]?
    public let drinkCategory: String?
    public let serving_size: String? // Add this field

    public static func == (lhs: ProductInfo, rhs: ProductInfo) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.volume == rhs.volume &&
               lhs.imageUrl == rhs.imageUrl &&
               lhs.keywords == rhs.keywords &&
               lhs.drinkCategory == rhs.drinkCategory &&
               lhs.serving_size == rhs.serving_size
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
    public func clearCache() {
            cachedProductInfo.removeAll()
            UserDefaults.standard.removeObject(forKey: userDefaultsProductInfoKey)
        }
        
        private func loadCachedProductInfo() {
            if let savedData = UserDefaults.standard.data(forKey: userDefaultsProductInfoKey) {
                do {
                    let decoder = JSONDecoder()
                    cachedProductInfo = try decoder.decode([String: ProductInfo].self, from: savedData)
                    print("Loaded cache with \(cachedProductInfo.count) items")
                    
                    // Debug: Print cached items
                    for (barcode, info) in cachedProductInfo {
                        print("Cached item:")
                        print("- Barcode: \(barcode)")
                        print("- Name: \(info.name)")
                        print("- Keywords: \(info.keywords ?? [])")
                        print("- DrinkCategory: \(info.drinkCategory ?? "nil")")
                    }
                } catch {
                    print("Error loading cache: \(error)")
                    // If there's an error loading the cache, clear it
                    clearCache()
                }
            }
        }
        
        private func saveProductInfo(_ product: ProductInfo) {
            print("Saving product to cache:")
            print("- Name: \(product.name)")
            print("- Keywords: \(product.keywords ?? [])")
            print("- DrinkCategory: \(product.drinkCategory ?? "nil")")
            
            cachedProductInfo[product.id] = product
            
            do {
                let encoder = JSONEncoder()
                let encoded = try encoder.encode(cachedProductInfo)
                UserDefaults.standard.set(encoded, forKey: userDefaultsProductInfoKey)
                print("Successfully saved to cache")
            } catch {
                print("Error saving to cache: \(error)")
            }
        }
    
    private func extractVolumeFromName(_ productName: String?) -> String? {
            guard let name = productName else { return nil }
            // Regex to match volume patterns in the product name
            let volumeRegex = try? NSRegularExpression(pattern: "(\\d+)\\s*(ml|cl|L|liters?|g|kg)", options: .caseInsensitive)
            let range = NSRange(location: 0, length: name.utf16.count)
            if let match = volumeRegex?.firstMatch(in: name, options: [], range: range) {
                let matchRange = match.range(at: 0)
                if matchRange.location != NSNotFound,
                   let matchedRange = Range(matchRange, in: name) {
                    return String(name[matchedRange])
                }
            }
            return nil
        }
    public func calculateWaterEstimate(
        quantity: String?,
        servingSize: String?,
        waterPercentage: Double?
    ) -> Double? {
        // If water percentage is not provided, return nil
        guard let waterPercentage = waterPercentage else { return nil }

        // Determine the base volume to use for calculation
        let baseVolume: String?
        if let servingSize = servingSize {
            baseVolume = servingSize // Use serving size if available
        } else {
            baseVolume = quantity ?? extractVolumeFromName(productInfo?.name) // Fallback to quantity or product name
        }

        // If no base volume is available, return nil
        guard let baseVolume = baseVolume else { return nil }

        // Extract numeric value from the base volume
        let volumeRegex = try? NSRegularExpression(pattern: "(\\d+)", options: [])
        let range = NSRange(location: 0, length: baseVolume.utf16.count)
        if let match = volumeRegex?.firstMatch(in: baseVolume, options: [], range: range),
           let matchRange = Range(match.range(at: 1), in: baseVolume),
           let volumeValue = Double(baseVolume[matchRange]) {
            // Calculate water content in milliliters (assuming percentage is out of 100)
            let waterContent = (volumeValue * waterPercentage) / 100.0
            return waterContent
        }

        return nil
    }
    public func lookupProductInformation(barcode: String) {
        isLoading = true
        errorMessage = nil
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else {
            handleError("Invalid URL")
            return
        }
        print("Making API call to: \(urlString)")
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    print("Network error: \(error)")
                    self.handleError(error.localizedDescription)
                    return
                }
                guard let data = data else {
                    print("No data received from API")
                    self.handleError("No product data received")
                    return
                }
                // Print raw response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Raw API Response: \(jsonString)")
                }
                do {
                    let apiResponse = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
                    guard let product = apiResponse.product else {
                        print("No product found in API response")
                        self.handleError("No product found")
                        return
                    }
                    print("API Response Product:")
                    print("- Name: \(product.product_name ?? "nil")")
                    print("- Keywords: \(product._keywords ?? [])")
                    
                    // Extract volume from quantity or fallback to product name
                    let volume = self.extractVolume(from: product.quantity) ??
                                 self.extractVolumeFromName(product.product_name) ??
                                 "Unknown Volume"
                    
                    // Extract serving size
                    let servingSize = product.serving_size
                    
                    // Determine drink category
                    let drinkCategory = self.determineDrinkCategory(
                        categories: product.categories,
                        genericName: product.generic_name
                    )
                    
                    // Calculate water estimate
                    let waterPercentage = product._keywords?.compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }.first
                    let waterEstimate = self.calculateWaterEstimate(
                        quantity: product.quantity,
                        servingSize: servingSize, // Pass serving size here
                        waterPercentage: waterPercentage
                    )
                    
                    // Create ProductInfo with water estimate
                    let productInfo = ProductInfo(
                        id: barcode,
                        name: product.product_name ?? "Unknown Product",
                        volume: volume,
                        imageUrl: product.image_url,
                        keywords: product._keywords,
                        drinkCategory: drinkCategory,
                        serving_size: product.serving_size
                    )
                    print("Created ProductInfo:")
                    print("- Keywords: \(productInfo.keywords ?? [])")
                    print("- Drink Category: \(productInfo.drinkCategory ?? "nil")")
                    print("- Water Estimate: \(String(describing: waterEstimate ?? 0.0))")
                    
                    self.productInfo = productInfo
                    self.showingScanResult = true
                } catch {
                    print("Decoding error: \(error)")
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
