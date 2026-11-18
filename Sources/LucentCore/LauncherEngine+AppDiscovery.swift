import Foundation

extension LauncherEngine {
    public static func discoverInstalledApps() -> [InstalledAppItem] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var seenPaths = Set<String>()
        var apps: [InstalledAppItem] = []

        func appendApp(at url: URL) {
            let path = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path), seenPaths.insert(path).inserted else { return }
            let eng = url.deletingPathExtension().lastPathComponent
            let locName = localizedName(forAppAt: url) ?? eng
            apps.append(InstalledAppItem(name: locName, englishName: eng, url: url))
        }

        appendApp(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items where url.pathExtension.lowercased() == "app" { appendApp(at: url) }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func localizedName(forAppAt url: URL) -> String? {
        let loctable = url.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        guard let data = try? Data(contentsOf: loctable),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let zh = (dict["zh_CN"] as? [String: Any]) ?? (dict["zh-Hans"] as? [String: Any])
        else { return nil }
        return (zh["CFBundleDisplayName"] as? String) ?? (zh["CFBundleName"] as? String)
    }
}
