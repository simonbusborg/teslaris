//
//  WidgetSnapshot.swift
//  TeslarisShared
//
//  The one channel between Teslaris and its widget. The app writes what it
//  has just fetched; the widget only ever reads. That direction is the whole
//  design: an extension refreshing on its own would mean two processes
//  holding the same OAuth session and racing each other's token refresh, and
//  the loser gets signed out — and every request it made would be billed
//  Fleet API traffic the credit gauge never saw. The widget is a view of the
//  app's last poll, never a second client.
//

import Foundation

/// What the widget needs to draw itself, and nothing more — no VIN, no
/// tokens, no account. The container is readable by anything in the app
/// group, so it stays free of anything worth stealing.
public struct WidgetSnapshot: Codable, Equatable {
    public var batteryPercentage: Double
    public var rangeKm: Int
    /// Tesla charging_state verbatim, e.g. "Charging" or "Disconnected".
    public var chargingState: String
    /// True when the numbers are the last known ones because the car is
    /// asleep — Teslaris never wakes it, and the widget shouldn't pretend
    /// otherwise.
    public var isAsleep: Bool
    public var fullInMinutes: Int?
    public var chargingPowerKw: Int?
    /// The owner's name for the car, or the model when it has none.
    public var carTitle: String?
    /// "Tesla Model Y". The small widget shows this rather than the name.
    public var modelName: String?
    public var odometerKm: Int?
    /// When the app last heard from the car.
    public var writtenAt: Date
    /// Travels with the data: a sandboxed extension has its own defaults
    /// domain and can't see the app's preference.
    public var unit: DistanceUnit
    public var hasImage: Bool

    // All optional: thin fixtures and old firmware report none of these.
    public var chargeLimitPercent: Int?
    public var doorsLocked: Bool?
    /// The menu's own wording for what is open ("A window, trunk open"),
    /// nil when everything is shut. Written by the app so the widget and
    /// the menu can never disagree on the phrasing.
    public var openText: String?
    /// "Preconditioning" or "Climate on", nil when the climate is off.
    public var climateText: String?

    public init(batteryPercentage: Double, rangeKm: Int, chargingState: String,
                isAsleep: Bool, fullInMinutes: Int?, chargingPowerKw: Int?,
                carTitle: String?, modelName: String?, odometerKm: Int?,
                writtenAt: Date, unit: DistanceUnit, hasImage: Bool,
                chargeLimitPercent: Int? = nil, doorsLocked: Bool? = nil,
                openText: String? = nil, climateText: String? = nil) {
        self.batteryPercentage = batteryPercentage
        self.rangeKm = rangeKm
        self.chargingState = chargingState
        self.isAsleep = isAsleep
        self.fullInMinutes = fullInMinutes
        self.chargingPowerKw = chargingPowerKw
        self.carTitle = carTitle
        self.modelName = modelName
        self.odometerKm = odometerKm
        self.writtenAt = writtenAt
        self.unit = unit
        self.hasImage = hasImage
        self.chargeLimitPercent = chargeLimitPercent
        self.doorsLocked = doorsLocked
        self.openText = openText
        self.climateText = climateText
    }

    /// The one thing worth a line on the medium widget beyond the battery:
    /// a running climate, something left open, or an unlocked car. nil when
    /// all is quiet, which is most of the time.
    public var attentionText: String? {
        if let climateText { return climateText }
        if let openText { return openText }
        if doorsLocked == false { return "Unlocked" }
        return nil
    }

    /// "Locked", "Unlocked", or what is open — what the Doors field shows.
    public var doorsText: String? {
        if let openText { return openText }
        guard let doorsLocked else { return nil }
        return doorsLocked ? "Locked" : "Unlocked"
    }

    /// Never while asleep: the state underneath is from before the car
    /// dozed off, and a green "charging" face on a car that finished hours
    /// ago would be a lie.
    public var isCharging: Bool {
        !isAsleep && (chargingState == "Charging" || chargingState == "Starting")
    }

    /// nil when the car reported a state this doesn't know.
    public var isPluggedIn: Bool? {
        switch chargingState {
        case "Charging", "Starting", "Complete", "Stopped", "NoPower": return true
        case "Disconnected": return false
        default: return nil
        }
    }

    /// Asleep wins: the charging state underneath it is from before the car
    /// dozed off.
    public var statusText: String {
        isAsleep ? "Asleep" : CarFormat.humanStatus(chargingState)
    }

    public var rangeText: String {
        CarFormat.distance(km: rangeKm, unit: unit)
    }

    /// Ignores `writtenAt`, so a poll that changed nothing doesn't count as
    /// a change. The app uses this to decide whether to spend a widget
    /// reload — on every poll, forever, on identical data would be nothing
    /// but battery.
    public func sameData(as other: WidgetSnapshot) -> Bool {
        var mine = self
        mine.writtenAt = other.writtenAt
        return mine == other
    }
}

/// The app group container, and the two files in it.
public enum SharedStore {

    private static let snapshotName = "snapshot.json"
    private static let imageName = "car.png"

    /// On macOS an App Group identifier carries the Team ID prefix, which is
    /// a secret rather than something to hard-code. The Makefile substitutes
    /// the assembled identifier into both Info.plists at build time and it is
    /// read back here — a build without a Team ID has no group at all, and
    /// every call below turns into a no-op rather than a wrong guess.
    public static var appGroup: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "TeslarisAppGroup") as? String
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Where the app and the widget meet.
    ///
    /// A signed build uses the App Group container. A local build can't:
    /// macOS validates an app group against the team in the signature, and an
    /// ad-hoc build has no team, so the container URL resolves and every read
    /// is then denied — which looks precisely like a bug in this file and
    /// isn't one. Such a build gets no group; its widget stays sandboxed but
    /// is granted read access to one plain folder (see
    /// scripts/make-entitlements.sh), and both processes meet there. Same
    /// code, working widget, no certificate needed to see it run.
    public static var containerURL: URL? {
        if let group = appGroup {
            // Deliberately no fallback here: a build that asked for a group
            // and didn't get one is broken, and should say so rather than
            // quietly write somewhere the other half won't look.
            return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        }
        return localURL
    }

    /// True when the two processes are talking through a real App Group,
    /// which is the only arrangement a released build ever uses.
    public static var isSharedGroup: Bool { appGroup != nil }

    /// Built from the real home directory rather than from FileManager or
    /// NSHomeDirectory, both of which answer with the sandbox container for a
    /// sandboxed process — so the widget would look inside its own container
    /// while the app wrote to the actual one, and each would be certain it
    /// was right. getpwuid reports the account's home either way, which is
    /// also the path the sandbox exception in make-entitlements.sh names.
    private static var localURL: URL? {
        var home = NSHomeDirectory()
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        }
        let directory = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Teslaris", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Why the widget has nothing to draw. An empty widget with one face for
    /// four different causes is what made the first round of this a guessing
    /// game, so the reason travels with the failure.
    public enum SnapshotState {
        case ok(WidgetSnapshot)
        /// No App Group at all — built without a Team ID.
        case noContainer
        /// The container is there but the app has never written to it.
        case noFile
        /// Written, but this build can't read it: a format the app and the
        /// widget disagree about, or a sandbox refusing the read.
        case unreadable(String)
    }

    public static func snapshotState() -> SnapshotState {
        guard let url = containerURL?.appendingPathComponent(snapshotName) else {
            return .noContainer
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return .noFile }
        do {
            return .ok(try decoder.decode(WidgetSnapshot.self, from: Data(contentsOf: url)))
        } catch {
            return .unreadable(String(describing: error).prefix(120).description)
        }
    }

    public static func loadSnapshot() -> WidgetSnapshot? {
        if case .ok(let snapshot) = snapshotState() { return snapshot }
        return nil
    }

    /// Atomic because the widget can wake up mid-write; a half-written file
    /// would decode to nil and blank the widget for one refresh.
    public static func save(_ snapshot: WidgetSnapshot) throws {
        guard let url = containerURL?.appendingPathComponent(snapshotName) else { return }
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    public static func loadImage() -> Data? {
        guard let url = containerURL?.appendingPathComponent(imageName) else { return nil }
        return try? Data(contentsOf: url)
    }

    public static var hasImage: Bool {
        guard let url = containerURL?.appendingPathComponent(imageName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func removeImage() {
        guard let url = containerURL?.appendingPathComponent(imageName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    public static func saveImage(_ data: Data) throws {
        guard let url = containerURL?.appendingPathComponent(imageName) else { return }
        try data.write(to: url, options: .atomic)
    }

    /// Signing out or removing the last car has to take the car off the
    /// desktop too — a widget still showing 78% for a car you no longer have
    /// is worse than an empty one.
    public static func clear() {
        guard let container = containerURL else { return }
        for name in [snapshotName, imageName] {
            try? FileManager.default.removeItem(at: container.appendingPathComponent(name))
        }
    }
}
