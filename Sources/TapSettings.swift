import Foundation

enum FinishMode: Int, Codable, CaseIterable {
    case count, duration, manual
    var title: String { ["按次数结束", "按时长结束", "手动停止"][rawValue] }
}

struct TapSettings: Codable {
    var intervalMS = 100
    var jitterMS = 50
    var pausePercent = 5
    var pauseMinMS = 500
    var pauseMaxMS = 1500
    var finishMode = FinishMode.count
    var count = 100
    var minutes = 10
    static let hold: TimeInterval = 0.020

    var validationError: String? {
        if !(30...10000).contains(intervalMS) { return "基础间隔需为 30–10000ms。" }
        if jitterMS < 0 || jitterMS > intervalMS - 30 { return "浮动需为非负数，且最短间隔不得小于 30ms。" }
        if !(0...100).contains(pausePercent) { return "暂停概率需为 0–100%。" }
        if !(100...60000).contains(pauseMinMS) || pauseMaxMS < pauseMinMS || pauseMaxMS > 60000 {
            return "暂停时长需为 100–60000ms，最长时间不得小于最短时间。"
        }
        if !(1...100_000_000).contains(count) { return "目标次数需为 1–100000000。" }
        if !(1...1440).contains(minutes) { return "目标时长需为 1–1440 分钟。" }
        return nil
    }

    /// Interval includes the hold; random rests are additional, after key-up.
    func nextStep() -> (interval: TimeInterval, pause: TimeInterval) {
        let interval = Double(Int.random(in: (intervalMS - jitterMS)...(intervalMS + jitterMS))) / 1000
        let pause = Int.random(in: 0..<100) < pausePercent
            ? Double(Int.random(in: pauseMinMS...pauseMaxMS)) / 1000 : 0
        return (interval, pause)
    }

    static func load() -> TapSettings {
        guard let data = UserDefaults.standard.data(forKey: "tapSettings"),
              let saved = try? JSONDecoder().decode(Self.self, from: data),
              saved.validationError == nil else { return Self() }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "tapSettings")
        }
    }
}
