import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#endif

// MARK: - USDA FoodData Central Response Models
struct USDAResponse: Codable {
    let foods: [USDAFood]?
}

struct USDAFood: Codable {
    let fdcId: Int? // Unique identifier for the food
    let description: String? // Product name
    let brandOwner: String? // Brand name
    let ingredients: String? // Ingredients list
    let foodNutrients: [FoodNutrient]? // Nutritional information
    let servingSize: Double? // Serving size in grams
    let servingSizeUnit: String? // Serving size unit (e.g., "g")
    let brandName: String? // Brand name (alternative)
    let packageWeight: String? // Package weight
    let foodCategory: String? // Food category (e.g., "Dairy")
}

struct FoodNutrient: Codable {
    let nutrientId: Int? // Nutrient ID
    let nutrientName: String? // Nutrient name (e.g., "Energy")
    let unitName: String? // Unit (e.g., "kcal")
    let value: Double? // Nutrient value
}
// MARK: - Product Information Model
public struct ProductInfo: Codable, Identifiable {
    public let id: String // FDC ID as unique identifier
    public let name: String
    public let brand: String
    public let servingSize: String
    public let ingredients: [String]
    public let nutritionalInfo: NutritionalInfo
    public let foodCategory: String?
    public let packageWeight: String?
    
    public struct NutritionalInfo: Codable {
        public let calories: Double
        public let protein: Double
        public let fat: Double
        public let carbohydrates: Double
        public let sugars: Double
        public let sodium: Double
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
    
    // USDA API Key
    private let usdaAPIKey = "v90Fya8DSiqx0kIJZv06Lc7Gjgrh6Kja1yJMwHrB"
    
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
    
    // MARK: - USDA FoodData Central Product Lookup
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
        
        // USDA FoodData Central API Endpoint
        let urlString = "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=\(usdaAPIKey)&query=\(barcode)"
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
                    let apiResponse = try JSONDecoder().decode(USDAResponse.self, from: data)
                    
                    // Validate response and product
                    guard let food = apiResponse.foods?.first else {
                        self.handleError("No product found")
                        return
                    }
                    
                    // Convert USDA food to our ProductInfo
                    let productInfo = ProductInfo(
                        id: String(food.fdcId ?? 0),
                        name: food.description ?? "Unknown Product",
                        brand: food.brandOwner ?? food.brandName ?? "Unknown Brand",
                        servingSize: "\(food.servingSize ?? 0) \(food.servingSizeUnit ?? "g")",
                        ingredients: self.extractIngredients(from: food.ingredients),
                        nutritionalInfo: ProductInfo.NutritionalInfo(
                            calories: self.extractNutrientValue(food.foodNutrients, nutrientName: "Energy"),
                            protein: self.extractNutrientValue(food.foodNutrients, nutrientName: "Protein"),
                            fat: self.extractNutrientValue(food.foodNutrients, nutrientName: "Total lipid (fat)"),
                            carbohydrates: self.extractNutrientValue(food.foodNutrients, nutrientName: "Carbohydrate, by difference"),
                            sugars: self.extractNutrientValue(food.foodNutrients, nutrientName: "Sugars, total including NLEA"),
                            sodium: self.extractNutrientValue(food.foodNutrients, nutrientName: "Sodium, Na")
                        ),
                        foodCategory: food.foodCategory,
                        packageWeight: food.packageWeight
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
    
    // Helper method to extract nutrient value
    private func extractNutrientValue(_ nutrients: [FoodNutrient]?, nutrientName: String) -> Double {
        return nutrients?.first { $0.nutrientName == nutrientName }?.value ?? 0.0
    }
    
    // Helper method to extract ingredients
    private func extractIngredients(from ingredientsText: String?) -> [String] {
        guard let ingredients = ingredientsText else { return [] }
        
        // Split ingredients by comma and clean up
        return ingredients
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

// MARK: - Product Scanner View
@available(iOS 14.0, macOS 13.0, *)
public struct ProductScannerView: View {
    @StateObject private var scannerService = ProductScannerService()
    @State private var showFullIngredients = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            BarcodeScannerPreviewView(scannerService: scannerService)
            
            VStack {
                Spacer()
                
                if scannerService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                } else {
                    Text("Scan Product Barcode")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }
            }
        }
        .sheet(isPresented: $scannerService.showingScanResult) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let error = scannerService.errorMessage {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .padding()
                    } else if let product = scannerService.productInfo {
                        // Product Details
                        Text(product.name)
                            .font(.title)
                        Text("Brand: \(product.brand)")
                            .font(.subheadline)
                        Text("Volume: \(product.servingSize) ml")
                        
                        // Ingredients Section
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Ingredients")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    showFullIngredients.toggle()
                                }) {
                                    Text(showFullIngredients ? "Collapse" : "Expand")
                                }
                            }
                            
                            if showFullIngredients {
                                ForEach(product.ingredients, id: \.self) { ingredient in
                                    Text("• \(ingredient)")
                                        .font(.caption)
                                }
                            } else {
                                Text(product.ingredients.prefix(3).joined(separator: ", "))
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical)
                        
                        // Nutritional Information
                        Text("Nutritional Information")
                            .font(.headline)
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Calories")
                                Spacer()
                                Text("\(product.nutritionalInfo.calories)")
                            }
                            HStack {
                                Text("Total Sugar")
                                Spacer()
                                Text("\(String(format: "%.1f", product.nutritionalInfo.sugars))g")
                            }
                            HStack {
                                Text("Protein")
                                Spacer()
                                Text("\(String(format: "%.1f", product.nutritionalInfo.protein))g")
                            }
                        }
                        
//                        // Allergens
//                        if !product.nutritionalInfo.calories {
//                            Text("Allergens")
//                                .font(.headline)
//                            ForEach(product.allergens, id: \.self) { allergen in
//                                Text("• \(allergen)")
//                                    .font(.caption)
//                            }
//                        }
                    } else {
                        Text("No product information found")
                            .foregroundColor(.red)
                    }
                    
                    Button("Scan Again") {
                        scannerService.showingScanResult = false
                        scannerService.errorMessage = nil
                        scannerService.startScanning()
                    }
                    .padding()
                }
                .padding()
            }
        }
    }
}
@available(iOS 13.0, macOS 13.0, *)
extension ProductScannerService {
    private func logProductInfo(_ product: ProductInfo) {
        print("Product Name: \(product.name)")
        print("Brand: \(product.brand)")
        print("Volume: \(product.servingSize) ml")
        print("Calories: \(product.nutritionalInfo.calories)")
        print("Ingredients: \(product.ingredients)")
    }
}
