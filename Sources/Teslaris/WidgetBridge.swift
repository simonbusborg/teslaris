//
//  WidgetBridge.swift
//  Teslaris
//
//  Publishes each poll to the shared container so the widget has something
//  to draw. Everything here is best-effort: if the container can't be
//  reached the app carries on exactly as it did before the widget existed.
//

import Foundation
import WidgetKit
import TeslarisShared

enum WidgetBridge {

    private static var lastWritten: WidgetSnapshot?
    /// Byte count of the render already in the container. The image only
    /// changes when the car does, so it is written once and then left alone.
    private static var lastImageBytes: Int?
    /// Whose render that is, so switching cars can't leave the previous
    /// car's picture beside the new car's numbers.
    private static var lastImageVin: String?

    /// `image` is the car render as PNG, nil while it is still downloading.
    static func publish(_ data: VehicleData, image: Data?) {
        guard SharedStore.containerURL != nil else { return }

        if let image {
            if image.count != lastImageBytes || data.vin != lastImageVin {
                do {
                    try SharedStore.saveImage(image)
                    lastImageBytes = image.count
                    lastImageVin = data.vin
                } catch {
                    // Not worth surfacing: the widget simply draws no car.
                    lastImageBytes = nil
                }
            }
        } else if data.vin != lastImageVin {
            // A different car, or the first poll after launch: better a
            // blank space than the wrong car until its render arrives.
            SharedStore.removeImage()
            lastImageBytes = nil
            lastImageVin = nil
        }

        let model = data.vin.flatMap { CarImage.modelName(vin: $0) }.map { "Tesla \($0)" }
        let name = data.vehicleName.flatMap { $0.isEmpty ? nil : $0 }
        var climate: String?
        if data.isPreconditioning == true {
            climate = "Preconditioning"
        } else if data.isClimateOn == true {
            climate = "Climate on"
        }

        let snapshot = WidgetSnapshot(
            batteryPercentage: data.batteryPercentage,
            rangeKm: data.rangeKm,
            chargingState: data.chargingState,
            isAsleep: data.isAsleep,
            fullInMinutes: data.minutesToFull,
            chargingPowerKw: data.chargingPowerKw,
            carTitle: name ?? model,
            modelName: model,
            odometerKm: data.odometerKm,
            // For a sleeping car this stays at the last real reading, which
            // is exactly what the widget's "updated" line should admit to.
            writtenAt: data.lastUpdated,
            unit: Preferences.distanceUnit,
            hasImage: SharedStore.hasImage,
            chargeLimitPercent: data.chargeLimitPercent,
            doorsLocked: data.locked,
            openText: StatusItemController.openSummary(for: data),
            climateText: climate
        )

        // The file is always rewritten so its timestamp stays honest, but a
        // poll that changed nothing isn't worth a reload: WidgetKit rations
        // those, and the widget rereads the file on its own every 15 minutes.
        let changed = lastWritten.map { !snapshot.sameData(as: $0) } ?? true
        do {
            try SharedStore.save(snapshot)
            lastWritten = snapshot
            if changed { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            NSLog("Teslaris: couldn't write the widget snapshot — \(error.localizedDescription)")
        }
    }

    /// Called when the session is gone. A widget still cheerfully showing
    /// 78% for a car you are no longer signed in to is worse than an empty
    /// one.
    static func clear() {
        lastWritten = nil
        lastImageBytes = nil
        lastImageVin = nil
        SharedStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
