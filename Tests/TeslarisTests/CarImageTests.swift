import XCTest
@testable import Teslaris

final class CarImageTests: XCTestCase {

    func testModelFromVin() {
        XCTAssertEqual(CarImage.modelCode(vin: "5YJSA1E26MF000000"), "ms")
        XCTAssertEqual(CarImage.modelCode(vin: "5YJ3E7EB0LF000000"), "m3")   // demo car
        XCTAssertEqual(CarImage.modelCode(vin: "5YJXCBE21KF000000"), "mx")
        XCTAssertEqual(CarImage.modelCode(vin: "7SAYGDEE5PA000000"), "my")   // Austin-built
        XCTAssertEqual(CarImage.modelCode(vin: "lrw3e7fs1nc000000"), "m3")   // case-insensitive
    }

    func testModelName() {
        XCTAssertEqual(CarImage.modelName(vin: "5YJ3E7EB0LF000000"), "Model 3")
        XCTAssertEqual(CarImage.modelName(vin: "7SAYGDEE5PA000000"), "Model Y")
        XCTAssertEqual(CarImage.modelName(vin: "7G2CEHED8RA000000"), "Cybertruck")
        XCTAssertNil(CarImage.modelName(vin: "5YJ"))
        XCTAssertNil(CarImage.modelName(vin: ""))
    }

    func testUnknownModelsHaveNoImage() {
        XCTAssertNil(CarImage.modelCode(vin: "7G2CEHED8RA000000"))   // Cybertruck
        XCTAssertNil(CarImage.modelCode(vin: ""))
        XCTAssertNil(CarImage.modelCode(vin: "5YJ"))
        XCTAssertNil(CarImage.url(vin: "7G2CEHED8RA000000"))
    }

    func testCompositorURL() {
        let url = CarImage.url(vin: "5YJ3E7EB0LF000000")?.absoluteString ?? ""
        XCTAssertTrue(url.hasPrefix("https://static-assets.tesla.com/configurator/compositor?"))
        XCTAssertTrue(url.contains("model=m3"))
        XCTAssertTrue(url.contains("view=STUD_SIDE"))
        XCTAssertTrue(url.contains("bkba_opt=1"))
        // All four option groups must be present or the compositor errors.
        XCTAssertTrue(url.contains("%24MT356,%24PPSW,%24W38A,%24IPB3"))
    }

    func testCustomOptionsOverride() {
        UserDefaults.standard.set("$MTY13,$PRED,$WY20P,$INPB0", forKey: "car_image_options")
        defer { UserDefaults.standard.removeObject(forKey: "car_image_options") }
        let url = CarImage.url(vin: "7SAYGDEE5PA000000")?.absoluteString ?? ""
        XCTAssertTrue(url.contains("options=%24MTY13,%24PRED,%24WY20P,%24INPB0"))
    }

    func testCustomOptionsBeatAutoDetection() {
        UserDefaults.standard.set("$MTY13,$PRED,$WY20P,$INPB0", forKey: "car_image_options")
        defer { UserDefaults.standard.removeObject(forKey: "car_image_options") }
        let url = CarImage.url(vin: "7SAYGDEE5PA000000", exteriorColor: "SolidBlack",
                               wheelType: "Induction20")?.absoluteString ?? ""
        XCTAssertTrue(url.contains("options=%24MTY13,%24PRED,%24WY20P,%24INPB0"))
    }

    func testAutoPaintAndWheels() {
        let url = CarImage.url(vin: "7SAYGDEE5PA000000", exteriorColor: "MidnightCherryRed",
                               wheelType: "Induction20")?.absoluteString ?? ""
        XCTAssertTrue(url.contains("%24MTY13,%24PR00,%24WY20P,%24INPB0"))
    }

    func testUnknownColorAndWheelsKeepDefaults() {
        let url = CarImage.url(vin: "7SAYGDEE5PA000000", exteriorColor: "ChromeDelete9000",
                               wheelType: "Hovercraft25")?.absoluteString ?? ""
        XCTAssertTrue(url.contains("%24MTY13,%24PPSW,%24WY19B,%24INPB0"))
    }

    /// The compositor 412s on codes a model's trim can't take — colors
    /// verified only for other models must fall back, not break the render.
    func testPaintCodesRespectModelSupport() {
        // RedMulticoat renders on S/X/Y but not the m3 (Highland) trim.
        let m3 = CarImage.url(vin: "5YJ3E7EB0LF000000", exteriorColor: "RedMulticoat")?
            .absoluteString ?? ""
        XCTAssertTrue(m3.contains("%24PPSW"))
        let my = CarImage.url(vin: "7SAYGDEE5PA000000", exteriorColor: "RedMulticoat")?
            .absoluteString ?? ""
        XCTAssertTrue(my.contains("%24PPMR"))
        // UltraRed is the reverse: 3/Y yes, S/X no.
        let ms = CarImage.url(vin: "5YJSA1E26MF000000", exteriorColor: "UltraRed")?
            .absoluteString ?? ""
        XCTAssertTrue(ms.contains("%24PPSW"))
    }
}
