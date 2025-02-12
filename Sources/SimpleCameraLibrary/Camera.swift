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
    let _keywords: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case product_name
        case quantity
        case image_url
        case categories
        case generic_name
        case _keywords = "_keywords"
    }
}

public struct ProductInfo: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let volume: String
    public let imageUrl: String?
    public let keywords: [String]?
    public let drinkCategory: String?
    
    public static func == (lhs: ProductInfo, rhs: ProductInfo) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.volume == rhs.volume &&
               lhs.imageUrl == rhs.imageUrl &&
               lhs.keywords == rhs.keywords &&
               lhs.drinkCategory == rhs.drinkCategory
    }
}

// MARK: - Product Scanner Service
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
    
    private var isProcessingBarcode = false
    private var lastScannedBarcode: String?
    private var lastScanTime: Date?
    private let scanCooldown: TimeInterval = 2.0
    private var isSessionConfigured = false
    private let sessionQueue = DispatchQueue(label: "com.scanner.sessionQueue", qos: .userInitiated)
    
    private let userDefaultsProductInfoKey = "SavedProductInformation"
    private var cachedProductInfo: [String: ProductInfo] = [:]
    
    public override init() {
        super.init()
        loadCachedProductInfo()
        checkPermissions()
    }
    
    // MARK: - Cache Management
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
                
                for (barcode, info) in cachedProductInfo {
                    print("Cached item:")
                    print("- Barcode: \(barcode)")
                    print("- Name: \(info.name)")
                    print("- Keywords: \(info.keywords ?? [])")
                    print("- DrinkCategory: \(info.drinkCategory ?? "nil")")
                }
            } catch {
                print("Error loading cache: \(error)")
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
    
    // MARK: - Product Information Lookup
    public func lookupProductInformation(barcode: String) {
        isLoading = true
        errorMessage = nil
        
        let urlString = "https://world.openfoodfacts.org/api/v2/product/\(barcode).json"
        guard let url = URL(string: urlString) else {
            handleError("Invalid URL")
            isProcessingBarcode = false
            return
        }
        
        print("Making API call to: \(urlString)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                self.isProcessingBarcode = false
                
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
                
                do {
                    let apiResponse = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
                    
                    guard let product = apiResponse.product else {
                        print("No product found in API response")
                        self.handleError("No product found")
                        return
                    }
                    
                    let volume = self.extractVolume(from: product.quantity) ?? "Unknown Volume"
                    let drinkCategory = self.determineDrinkCategory(
                        categories: product.categories,
                        genericName: product.generic_name
                    )
                    
                    let productInfo = ProductInfo(
                        id: barcode,
                        name: product.product_name ?? "Unknown Product",
                        volume: volume,
                        imageUrl: product.image_url,
                        keywords: product._keywords,
                        drinkCategory: drinkCategory
                    )
                    
                    self.saveProductInfo(productInfo)
                    self.productInfo = productInfo
                    self.showingScanResult = true
                    self.stopScanning()
                    
                } catch {
                    print("Decoding error: \(error)")
                    self.handleError("Failed to decode product information: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    // MARK: - Helper Methods
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
    
    private func extractVolume(from quantityString: String?) -> String? {
        guard let quantity = quantityString else { return nil }
        
        let volumeRegex = try? NSRegularExpression(pattern: "(\\d+)\\s*(ml|cl|L|liters?|g|kg)", options: .caseInsensitive)
        let range = NSRange(location: 0, length: quantity.utf16.count)
        
        if let match = volumeRegex?.firstMatch(in: quantity, options: [], range: range) {
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
            self.isProcessingBarcode = false
        }
    }
    
    // MARK: - Camera Setup and Control
    private func setupBarcodeScanner() {
        guard !isSessionConfigured else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.session.beginConfiguration()
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: .back) else { return }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                if self.session.canAddOutput(self.metadataOutput) {
                    self.session.addOutput(self.metadataOutput)
                    self.metadataOutput.metadataObjectTypes = [
                        .ean8, .ean13, .qr, .code128, .code39, .code93, .upce
                    ]
                }
                
                self.session.commitConfiguration()
                self.isSessionConfigured = true
            } catch {
                print("Error setting up barcode scanner: \(error.localizedDescription)")
            }
        }
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupBarcodeScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupBarcodeScanner()
                }
            }
        default:
            return
        }
    }
    
    public func startScanning() {
        resetScanningState()
        
        if !isSessionConfigured {
            setupBarcodeScanner()
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    public func stopScanning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    public func resetScanningState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isProcessingBarcode = false
            self.lastScannedBarcode = nil
            self.lastScanTime = nil
            self.errorMessage = nil
            self.showingScanResult = false
            self.productInfo = nil
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate
@available(iOS 13.0, macOS 13.0, *)
extension ProductScannerService: AVCaptureMetadataOutputObjectsDelegate {
    public func metadataOutput(_ output: AVCaptureMetadataOutput,
                             didOutput metadataObjects: [AVMetadataObject],
                             from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let barcode = metadataObject.stringValue else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard !self.isProcessingBarcode else {
                return
            }
            
            if let lastBarcode = self.lastScannedBarcode,
               let lastTime = self.lastScanTime,
               lastBarcode == barcode &&
                Date().timeIntervalSince(lastTime) < self.scanCooldown {
                return
            }
            
            self.isProcessingBarcode = true
            self.lastScannedBarcode = barcode
            self.lastScanTime = Date()
            self.scannedBarcode = barcode
            
            if let cachedProduct = self.cachedProductInfo[barcode] {
                self.productInfo = cachedProduct
                self.showingScanResult = true
                self.stopScanning()
                self.isProcessingBarcode = false
                return
            }
            
            self.lookupProductInformation(barcode: barcode)
        }
    }
}

// MARK: - Preview View
#if os(iOS)
@available(iOS 13.0, *)
public struct BarcodeScannerPreviewView: UIViewRepresentable {
    @ObservedObject var scannerService: ProductScannerService
    
    public init(scannerService: ProductScannerService) {
        self.scannerService = scannerService
    }
    
    public func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: scannerService.session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        
        if let connection = previewLayer.connection {
            connection.videoOrientation = .portrait
        }
        
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.main.async {
            scannerService.preview = previewLayer
            scannerService.startScanning()
        }
        
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
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: scannerService.session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspect
        
        view.layer = previewLayer
        
        DispatchQueue.main.async {
            scannerService.preview = previewLayer
            scannerService.startScanning()
        }
        
        return view
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
