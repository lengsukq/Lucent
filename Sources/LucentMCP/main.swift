import Foundation
import LucentCore

var pluginsDir = PluginSystem.defaultPluginsDirectory()
var homeLayoutURL: URL? = nil
var generalPrefsURL: URL? = nil
var indexCacheDir: URL? = nil
let args = CommandLine.arguments
if let flagIndex = args.firstIndex(of: "--plugins-dir"), flagIndex + 1 < args.count {
    pluginsDir = URL(fileURLWithPath: args[flagIndex + 1], isDirectory: true)
}
if let layoutIndex = args.firstIndex(of: "--home-layout"), layoutIndex + 1 < args.count {
    homeLayoutURL = URL(fileURLWithPath: args[layoutIndex + 1], isDirectory: false)
}
if let prefsIndex = args.firstIndex(of: "--general-prefs"), prefsIndex + 1 < args.count {
    generalPrefsURL = URL(fileURLWithPath: args[prefsIndex + 1], isDirectory: false)
}
if let cacheIndex = args.firstIndex(of: "--index-cache"), cacheIndex + 1 < args.count {
    indexCacheDir = URL(fileURLWithPath: args[cacheIndex + 1], isDirectory: true)
}

MCPServer(
    pluginsDirectory: pluginsDir,
    customHomeLayoutURL: homeLayoutURL,
    customGeneralPrefsURL: generalPrefsURL,
    customIndexCacheDirectory: indexCacheDir
).runStdioLoop()
