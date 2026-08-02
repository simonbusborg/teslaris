//
//  CarImage.swift
//  Teslaris
//
//  Side-view render of the car for the top of the menu, from Tesla's
//  configurator compositor (static-assets.tesla.com). Unofficial but
//  Tesla-hosted, unauthenticated, and free — a static asset, not billed
//  Fleet API traffic. The model is derived from the VIN; paint and wheels
//  come from vehicle_config when the API reports a combination the
//  compositor is verified to accept, otherwise neutral defaults. Any
//  failure just means no image row — nothing else breaks.
//

import AppKit

enum CarImage {

    /// VIN position 4 encodes the model line across every Tesla plant
    /// prefix (5YJ3…, 7SAY…, XP7Y…, LRW3…). Cybertruck is omitted — its
    /// compositor option codes are not publicly known.
    static func modelCode(vin: String) -> String? {
        guard vin.count >= 4 else { return nil }
        switch Array(vin.uppercased())[3] {
        case "S": return "ms"
        case "3": return "m3"
        case "X": return "mx"
        case "Y": return "my"
        default: return nil
        }
    }

    /// Human name for the menu ("Model 3"); nil when the VIN is unknown.
    /// Cybertruck gets a name even though it gets no compositor image.
    static func modelName(vin: String) -> String? {
        guard vin.count >= 4 else { return nil }
        switch Array(vin.uppercased())[3] {
        case "S": return "Model S"
        case "3": return "Model 3"
        case "X": return "Model X"
        case "Y": return "Model Y"
        case "C": return "Cybertruck"
        default: return nil
        }
    }

    /// Verified-working option sets. The compositor errors (404/412)
    /// unless all four groups are present: trim, paint, wheels, interior.
    private static let defaultOptions: [String: (trim: String, paint: String,
                                                 wheels: String, interior: String)] = [
        "ms": ("MTS14", "PPSW", "WS90", "IBE00"),
        "m3": ("MT356", "PPSW", "W38A", "IPB3"),
        "mx": ("MTX14", "PPSW", "WX00", "IBE00"),
        "my": ("MTY13", "PPSW", "WY19B", "INPB0"),
    ]

    /// vehicle_config.exterior_color → compositor paint code, per model.
    /// The compositor rejects (412) any code the model's trim can't take —
    /// e.g. the m3 trim is the current Highland, which dropped
    /// MidnightSilver/RedMulticoat — so every entry here was probed
    /// against the live compositor. Unmapped colors keep the white default.
    private static let paintCodes: [String: [String: String]] = {
        var codes: [String: [String: String]] = [:]
        for model in ["ms", "m3", "mx", "my"] {
            codes[model] = ["PearlWhite": "PPSW", "White": "PPSW",
                            "SolidBlack": "PBSB", "Black": "PBSB",
                            "DeepBlue": "PPSB", "DeepBlueMetallic": "PPSB"]
        }
        for model in ["ms", "mx", "my"] {
            codes[model]?["MidnightSilver"] = "PMNG"
            codes[model]?["MidnightSilverMetallic"] = "PMNG"
            codes[model]?["Red"] = "PPMR"
            codes[model]?["RedMulticoat"] = "PPMR"
        }
        for model in ["m3", "my"] {
            codes[model]?["UltraRed"] = "PR01"
            codes[model]?["Quicksilver"] = "PN00"
            codes[model]?["StealthGrey"] = "PN01"
        }
        codes["my"]?["MidnightCherryRed"] = "PR00"
        return codes
    }()

    /// vehicle_config.wheel_type → compositor wheel code, likewise
    /// verified per model. Unmapped wheels keep the model's default.
    private static let wheelCodes: [String: [String: String]] = [
        "ms": ["Tempest19": "WS90", "Arachnid21": "WS10"],
        "m3": ["Photon18": "W38A", "Nova19": "W39S"],
        "mx": ["Cyberstream20": "WX00", "Turbine22": "WX20"],
        "my": ["Gemini19": "WY19B", "Induction20": "WY20P"],
    ]

    /// Escape hatch to force exact options without any UI (wins over the
    /// auto-detected paint and wheels):
    ///   defaults write com.weareheavy.teslaris car_image_options '$MTY13,$PRED,$WY20P,$INPB0'
    static func url(vin: String, exteriorColor: String? = nil,
                    wheelType: String? = nil) -> URL? {
        guard let model = modelCode(vin: vin) else { return nil }
        let options: String
        if let custom = UserDefaults.standard.string(forKey: "car_image_options"),
           !custom.isEmpty {
            options = custom.replacingOccurrences(of: "$", with: "%24")
        } else if let d = defaultOptions[model] {
            let paint = exteriorColor.flatMap { paintCodes[model]?[$0] } ?? d.paint
            let wheels = wheelType.flatMap { wheelCodes[model]?[$0] } ?? d.wheels
            options = "%24\(d.trim),%24\(paint),%24\(wheels),%24\(d.interior)"
        } else {
            return nil
        }
        return URL(string: "https://static-assets.tesla.com/configurator/compositor"
            + "?model=\(model)&options=\(options)&view=STUD_SIDE&size=800&bkba_opt=1")
    }
}

/// Fetches and caches one image per compositor URL — the URL for a VIN
/// changes once vehicle_config supplies real paint and wheels, and the
/// fresher render then replaces the neutral default. Misses render
/// nothing; the menu is rebuilt on every refresh anyway, so a late
/// arrival shows up via `onLoad` re-rendering.
final class CarImageLoader {

    var onLoad: (() -> Void)?
    private var cache: [String: NSImage] = [:]
    private var inflight: Set<String> = []

    func image(for vin: String, exteriorColor: String? = nil,
               wheelType: String? = nil) -> NSImage? {
        guard let url = CarImage.url(vin: vin, exteriorColor: exteriorColor,
                                     wheelType: wheelType) else { return nil }
        let key = url.absoluteString
        if let image = cache[key] { return image }
        guard !inflight.contains(key) else { return nil }
        inflight.insert(key)
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inflight.remove(key)   // a failure retries on the next render
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let data, let image = NSImage(data: data) else { return }
                self.cache[key] = image
                self.onLoad?()
            }
        }.resume()
        return nil
    }
}

/// Menu row drawing the render trimmed of its transparent letterboxing
/// (the car occupies only the middle band of the compositor's canvas).
final class CarImageRowView: NSView {

    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(x: 0, y: 0, width: StatusItemController.rowWidth, height: 100))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let source = NSRect(x: 0, y: size.height * 0.22,
                            width: size.width, height: size.height * 0.60)
        let width = bounds.width - 24
        let height = width * source.height / source.width
        image.draw(in: NSRect(x: 12, y: (bounds.height - height) / 2,
                              width: width, height: height),
                   from: source, operation: .sourceOver, fraction: 1)
    }
}
