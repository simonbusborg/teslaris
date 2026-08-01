//
//  CarImage.swift
//  Teslaris
//
//  Side-view render of the car for the top of the menu, from Tesla's
//  configurator compositor (static-assets.tesla.com). Unofficial but
//  Tesla-hosted, unauthenticated, and free — a static asset, not billed
//  Fleet API traffic. The model is derived from the VIN; paint and trim
//  are fixed neutral defaults (the right *model* matters, the color
//  doesn't). Any failure just means no image row — nothing else breaks.
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

    /// Verified-working option sets, already percent-encoded ($ → %24).
    /// The compositor errors (404/412) unless all four groups are present:
    /// trim, paint, wheels, interior.
    private static let defaultOptions = [
        "ms": "%24MTS14,%24PPSW,%24WS90,%24IBE00",
        "m3": "%24MT356,%24PPSW,%24W38A,%24IPB3",
        "mx": "%24MTX14,%24PPSW,%24WX00,%24IBE00",
        "my": "%24MTY13,%24PPSW,%24WY19B,%24INPB0",
    ]

    /// Escape hatch to match your actual car without any UI:
    ///   defaults write com.weareheavy.teslaris car_image_options '$MTY13,$PRED,$WY20P,$INPB0'
    static func url(vin: String) -> URL? {
        guard let model = modelCode(vin: vin) else { return nil }
        var options = defaultOptions[model] ?? ""
        if let custom = UserDefaults.standard.string(forKey: "car_image_options"),
           !custom.isEmpty {
            options = custom.replacingOccurrences(of: "$", with: "%24")
        }
        guard !options.isEmpty else { return nil }
        return URL(string: "https://static-assets.tesla.com/configurator/compositor"
            + "?model=\(model)&options=\(options)&view=STUD_SIDE&size=800&bkba_opt=1")
    }
}

/// Fetches and caches one image per VIN. Misses render nothing; the menu
/// is rebuilt on every refresh anyway, so a late arrival shows up via
/// `onLoad` re-rendering.
final class CarImageLoader {

    var onLoad: (() -> Void)?
    private var cache: [String: NSImage] = [:]
    private var inflight: Set<String> = []

    func image(for vin: String) -> NSImage? {
        if let image = cache[vin] { return image }
        guard !inflight.contains(vin), let url = CarImage.url(vin: vin) else { return nil }
        inflight.insert(vin)
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inflight.remove(vin)   // a failure retries on the next render
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let data, let image = NSImage(data: data) else { return }
                self.cache[vin] = image
                self.onLoad?()
            }
        }.resume()
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
