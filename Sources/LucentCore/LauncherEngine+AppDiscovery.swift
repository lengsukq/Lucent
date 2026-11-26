import Darwin
import Foundation

extension LauncherEngine {
    public static let maxAppSubfolderDepth = 2
    private static let nonTraversableBundleExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "appex", "qlgenerator",
        "mdimporter", "prefpane", "saver", "xpc", "kext", "systemextension", "driver",
        "swiftmodule", "xcodeproj", "xcworkspace", "playground"
    ]
    private static let appFingerprintRelativePaths: [String] = [
        "Contents/Info.plist",
        "Contents/Resources",
        "Contents/Resources/InfoPlist.loctable",
        "Contents/Resources/zh-Hans.lproj/InfoPlist.strings",
        "Contents/Resources/zh_CN.lproj/InfoPlist.strings",
        "Contents/Resources/zh-Hant.lproj/InfoPlist.strings",
        "Contents/Resources/en.lproj/InfoPlist.strings",
        "Contents/Resources/Assets.car",
        "Icon\r"
    ]

    private struct DirectoryIdentity: Hashable {
        let dev: dev_t
        let ino: ino_t
    }

    public static func defaultApplicationRootURLs() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
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
        var seenCanonicalPaths = Set<String>()
        var visitedMinDepth: [DirectoryIdentity: Int] = [:]
        var apps: [InstalledAppItem] = []

        func appendApp(at url: URL) {
            let canonicalPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: canonicalPath, isDirectory: &isDir), isDir.boolValue,
                  seenCanonicalPaths.insert(canonicalPath).inserted else { return }
            let stem = url.deletingPathExtension().lastPathComponent
            let eng = englishLocalizedName(forAppAt: url) ?? stem
            let locName = localizedName(forAppAt: url) ?? eng
            apps.append(InstalledAppItem(name: locName, englishName: eng, url: url))
        }

        if includeFinder {
            appendApp(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        }

        // BFS guarantees deterministic order, visits shallower real dirs before deeper symlinks,
        // and registers real .app bundles ahead of sibling symlinks pointing to the same target.
        var queue: [(url: URL, depth: Int)] = roots.map { ($0, 0) }
        var head = 0
        var deferredSymlinkApps: [URL] = []

        while head < queue.count {
            let current = queue[head]
            head += 1
            var st = stat()
            guard current.url.path.withCString({ stat($0, &st) == 0 }), (st.st_mode & S_IFMT) == S_IFDIR else { continue }
            let identity = DirectoryIdentity(dev: st.st_dev, ino: st.st_ino)
            if let prevDepth = visitedMinDepth[identity], prevDepth <= current.depth { continue }
            visitedMinDepth[identity] = current.depth

            guard let rawItems = try? fm.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            let sortedItems = rawItems.sorted { $0.lastPathComponent < $1.lastPathComponent }

            for item in sortedItems {
                let extLower = item.pathExtension.lowercased()
                if extLower == "app" {
                    let isSymlink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
                    if isSymlink { deferredSymlinkApps.append(item) } else { appendApp(at: item) }
                    continue
                }
                guard current.depth < maxAppSubfolderDepth, !nonTraversableBundleExtensions.contains(extLower) else { continue }
                queue.append((item, current.depth + 1))
            }
        }
        for aliasURL in deferredSymlinkApps { appendApp(at: aliasURL) }

        return apps.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public static func applicationDirectoriesFingerprint(roots customRoots: [URL]? = nil) -> UInt64 {
        let roots = customRoots ?? defaultApplicationRootURLs()
        let fm = FileManager.default
        var hash: UInt64 = 14_695_981_039_346_656_037
        var visitedMinDepth: [DirectoryIdentity: Int] = [:]

        func mix(_ value: UInt64) {
            hash ^= value
            hash &*= 1_099_511_628_211
        }
        func mixString(_ text: String) {
            for b in text.utf8 { mix(UInt64(b)) }
            mix(0xFF)
        }
        func mixStat(_ st: stat) {
            mix(UInt64(bitPattern: Int64(st.st_dev)))
            mix(st.st_ino)
            mix(UInt64(bitPattern: Int64(st.st_mtimespec.tv_sec)))
            mix(UInt64(bitPattern: Int64(st.st_mtimespec.tv_nsec)))
            mix(UInt64(bitPattern: Int64(st.st_ctimespec.tv_sec)))
            mix(UInt64(bitPattern: Int64(st.st_ctimespec.tv_nsec)))
            mix(UInt64(bitPattern: st.st_size))
        }
        func mixPathStat(at path: String, followSymlinks: Bool) -> stat? {
            var st = stat()
            let ok = path.withCString { followSymlinks ? stat($0, &st) == 0 : lstat($0, &st) == 0 }
            guard ok else { mix(0xDEAD_BEEF); return nil }
            mixStat(st)
            return st
        }
        func mixAppBundle(_ appURL: URL) {
            let path = appURL.path
            _ = mixPathStat(at: path, followSymlinks: false)
            guard mixPathStat(at: path, followSymlinks: true) != nil else { return }
            for rel in appFingerprintRelativePaths {
                _ = mixPathStat(at: "\(path)/\(rel)", followSymlinks: true)
            }
        }

        var queue: [(url: URL, depth: Int)] = roots.map { ($0, 0) }
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let dirPath = current.url.standardizedFileURL.path
            mixString(dirPath)
            guard let st = mixPathStat(at: dirPath, followSymlinks: true),
                  (st.st_mode & S_IFMT) == S_IFDIR else { continue }
            let identity = DirectoryIdentity(dev: st.st_dev, ino: st.st_ino)
            if let prevDepth = visitedMinDepth[identity], prevDepth <= current.depth { continue }
            visitedMinDepth[identity] = current.depth
            guard let children = try? fm.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let extLower = child.pathExtension.lowercased()
                if extLower == "app" {
                    mixString(child.lastPathComponent)
                    mixAppBundle(child)
                    continue
                }
                guard current.depth < maxAppSubfolderDepth, !nonTraversableBundleExtensions.contains(extLower) else { continue }
                queue.append((child, current.depth + 1))
            }
        }
        return hash
    }

    public static func englishLocalizedName(forAppAt url: URL) -> String? {
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)
        let loctable = resources.appendingPathComponent("InfoPlist.loctable")
        if let data = try? Data(contentsOf: loctable),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let en = (dict["en"] as? [String: Any]) ?? (dict["en_US"] as? [String: Any]),
           let name = nonEmptyDisplayName(from: en) {
            return name
        }
        for lproj in ["en.lproj", "English.lproj"] {
            let stringsURL = resources.appendingPathComponent(lproj, isDirectory: true)
                .appendingPathComponent("InfoPlist.strings")
            if let data = try? Data(contentsOf: stringsURL),
               let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let name = nonEmptyDisplayName(from: dict) {
                return name
            }
        }
        return nil
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
