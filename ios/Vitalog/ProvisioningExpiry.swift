import Foundation

enum ProvisioningExpiry {
    static var date: Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        return object?["ExpirationDate"] as? Date
    }

    static func daysLeft(until expiry: Date, from now: Date = Date()) -> Int {
        Calendar.current.dateComponents([.day], from: now, to: expiry).day ?? 0
    }
}
