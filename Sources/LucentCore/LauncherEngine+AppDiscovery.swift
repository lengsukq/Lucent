import Darwin
import Foundation

extension LauncherEngine {
    private static let nonTraversableBundleExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "appex", "qlgenerator",
        "mdimporter", "prefpane", "saver", "xpc", "kext", "systemextension", "driver"
    ]

    public static func defaultApplicationRootURLs() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    public static func discoverInstalledApps(
        roots customRoots: [URL]? = nil,
        includeCoreServicesFinder: Bool? = nil
    ) -> [InstalledAppItem] {
        let roots = customRoots ?? defaultApplicationRootURLs()
        let includeFinder = includeCoreServicesFinder ?? (customRoots == nil)
        let fm = FileManager.default
        var seenPaths = Set<String>()
        var apps: [InstalledAppItem] = []

        func appendApp(at url: URL) {
            let canonicalPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard fm.fileExists(atPath: canonicalPath), seenPaths.insert(canonicalPath).inserted else { return }
            let eng = url.deletingPathExtension().lastPathComponent
            let locName = localizedName(forAppAt: url) ?? eng
            apps.append(InstalledAppItem(name: locName, englishName: eng, url: url))
        }

        if includeFinder {
            appendApp(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        }

        let dirKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: dirKeys,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in items {
                let extLower = item.pathExtension.lowercased()
                if extLower == "app" {
                    appendApp(at: item)
                    continue
                }
                guard !nonTraversableBundleExtensions.contains(extLower) else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }
                guard let nested = try? fm.contentsOfDirectory(
                    at: item,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for child in nested where child.pathExtension.lowercased() == "app" {
                    appendApp(at: child)
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func applicationDirectoriesFingerprint(roots customRoots: [URL]? = nil) -> UInt64 {
        let roots = customRoots ?? defaultApplicationRootURLs()
        let fm = FileManager.default
        var hash: UInt64 = 14_695_981_039_346_656_037

        func mix(_ value: UInt64) {
            hash ^= value
            hash &*= 1_099_511_628_211
        }

        func mixDirectoryStat(at path: String) -> Bool {
            var st = stat()
            guard path.withCString({ stat($0, &st) == 0 }), (st.st_mode & S_IFMT) == S_IFDIR else {
                mix(0xDEAD_BEEF)
                return false
            }
            mix(UInt64(bitPattern: Int64(st.st_dev)))
            mix(st.st_ino)
            mix(UInt64(bitPattern: Int64(st.st_mtimespec.tv_sec)))
            mix(UInt64(bitPattern: Int64(st.st_mtimespec.tv_nsec)))
            mix(UInt64(bitPattern: st.st_size))
            return true
        }

        for root in roots {
            let rootPath = root.standardizedFileURL.path
            guard mixDirectoryStat(at: rootPath),
                  let children = try? fm.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                  ) else { continue }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let extLower = child.pathExtension.lowercased()
                guard !nonTraversableBundleExtensions.contains(extLower) else { continue }
                _ = mixDirectoryStat(at: child.path)
            }
        }
        return hash
    }

    public static func localizedName(forAppAt url: URL) -> String? {
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        let loctable = resources.appendingPathComponent("InfoPlist.loctable")
        if let data = try? Data(contentsOf: loctable),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let zh = (dict["zh_CN"] as? [String: Any])
                ?? (dict["zh-Hans"] as? [String: Any])
                ?? (dict["zh_Hans"] as? [String: Any]),
           let name = nonEmptyDisplayName(from: zh) {
            return name
        }

        for lproj in ["zh-Hans.lproj", "zh_CN.lproj", "zh-Hant.lproj"] {
            let stringsURL = resources.appendingPathComponent(lproj, isDirectory: true)
                .appendingPathComponent("InfoPlist.strings")
            if let data = try? Data(contentsOf: stringsURL),
               let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let name = nonEmptyDisplayName(from: dict) {
                return name
            }
        }

        let infoPlist = url.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: infoPlist),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let raw = dict["CFBundleDisplayName"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func nonEmptyDisplayName(from dict: [String: Any]) -> String? {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let val = dict[key] as? String {
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}
