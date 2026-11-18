import Foundation
import LucentCore

var pluginsDir = PluginSystem.defaultPluginsDirectory()
var homeLayoutURL: URL? = nil
let args = CommandLine.arguments
if let flagIndex = args.firstIndex(of: "--plugins-dir"), flagIndex + 1 < args.count {
    pluginsDir = URL(fileURLWithPath: args[flagIndex + 1], isDirectory: true)
}
if let layoutIndex = args.firstIndex(of: "--home-layout"), layoutIndex + 1 < args.count {
    homeLayoutURL = URL(fileURLWithPath: args[layoutIndex + 1], isDirectory: false)
}

MCPServer(pluginsDirectory: pluginsDir, customHomeLayoutURL: homeLayoutURL).runStdioLoop()
