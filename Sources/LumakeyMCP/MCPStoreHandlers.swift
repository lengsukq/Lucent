import Dispatch
import Foundation
import LumakeyCore

extension MCPServer {
    func storeToolSchemas() -> [[String: Any]] {
        [
            schema(
                "lumakey_package_plugin_for_store",
                "Validate an external plugin against Spec v3, package a clean `<id>.zip` archive, compute its 64-hex SHA-256 digest, and optionally create or update a `lumakey-registry.json` custom store manifest.",
                [
                    "id": ["type": "string", "description": "External plugin ID in the Plugins directory."],
                    "outputDir": ["type": "string", "description": "Absolute directory path where `<id>.zip` will be written."],
                    "downloadURL": ["type": "string", "description": "Optional public HTTPS or relative URL (default `./<id>.zip`) written into the registry entry."],
                    "registryPath": ["type": "string", "description": "Optional path to `lumakey-registry.json` to create or update."],
                    "storeId": ["type": "string", "description": "Store identifier (`[a-z0-9-]+`, default `custom-store`) used when creating a new registry."],
                    "storeName": ["type": "string", "description": "Display name of the custom store when creating a new registry."],
                    "maintainer": ["type": "string", "description": "Optional store maintainer name."],
                    "minAppVersion": ["type": "string", "description": "Optional minimum Lumakey version string (e.g. `0.8.8`)."]
                ],
                ["id", "outputDir"]
            ),
            schema(
                "lumakey_list_plugin_stores",
                "List all subscribed custom plugin store registries (`plugin-registries.json`) and their discovered plugins.",
                [:],
                []
            ),
            schema(
                "lumakey_resolve_or_install_url",
                "Auto-detect whether a URL or local path points to a custom plugin store (`lumakey-registry.json`) or a standalone plugin (`.zip` / `plugin.json` / repo), subscribe the store or optionally install the plugin.",
                [
                    "url": ["type": "string", "description": "Store URL, single plugin archive/manifest URL, GitHub repo URL, or local file/directory path."],
                    "install": ["type": "boolean", "description": "For a single plugin, install it after validation (default false = preview only). For a store, install `installPluginId` if specified."],
                    "installPluginId": ["type": "string", "description": "Optional plugin ID inside the resolved store registry to install immediately."]
                ],
                ["url"]
            )
        ]
    }

    var storeAppSupportDirectory: URL {
        pluginsDirectory.standardizedFileURL.deletingLastPathComponent()
    }

    func handlePackagePluginForStore(arguments: [String: Any]) -> [String: Any] {
        let id = arguments["id"] as? String ?? ""
        let rawOut = arguments["outputDir"] as? String ?? ""
        guard !id.isEmpty, !rawOut.isEmpty else {
            return textResult("Missing required arguments 'id' and 'outputDir'.", isError: true)
        }
        let outURL = URL(fileURLWithPath: (rawOut as NSString).expandingTildeInPath, isDirectory: true)
        let regURL = (arguments["registryPath"] as? String).flatMap { raw -> URL? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: false)
        }
        do {
            let artifact = try PluginStorePackager.packagePluginForStore(
                pluginID: id,
                in: pluginsDirectory,
                outputDirectory: outURL,
                downloadURL: arguments["downloadURL"] as? String,
                minAppVersion: arguments["minAppVersion"] as? String,
                updateRegistryAt: regURL,
                storeId: (arguments["storeId"] as? String) ?? "custom-store",
                storeName: (arguments["storeName"] as? String) ?? "Custom Lumakey Store",
                maintainer: arguments["maintainer"] as? String
            )
            let itemData = (try? JSONEncoder().encode(artifact.registryItem)) ?? Data()
            let itemDict = (try? JSONSerialization.jsonObject(with: itemData) as? [String: Any]) ?? [:]
            let regPathValue: Any = artifact.registryFileURL?.path ?? NSNull()
            let payload: [String: Any] = [
                "ok": true,
                "archivePath": artifact.archiveURL.path,
                "sha256": artifact.sha256,
                "sizeBytes": artifact.sizeBytes,
                "registryPath": regPathValue,
                "registryEntry": itemDict
            ]
            return textResult(prettyJSON(payload))
        } catch {
            let msg = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
            return textResult("Package error: \(msg)", isError: true)
        }
    }

    func handleListPluginStores() -> [String: Any] {
        let catalog = PluginStoreService.loadCatalog(appSupportDirectory: storeAppSupportDirectory)
        let stores = catalog.stores.map { sub -> [String: Any] in
            let maintainerVal: Any = sub.manifest.maintainer ?? NSNull()
            return [
                "storeId": sub.id,
                "storeName": sub.manifest.storeName,
                "maintainer": maintainerVal,
                "sourceURL": sub.sourceURL,
                "resolvedRegistryURL": sub.resolvedRegistryURL,
                "lastSyncedAt": sub.lastSyncedAtISO8601,
                "pluginCount": sub.manifest.plugins.count,
                "plugins": sub.manifest.plugins.map { p -> [String: Any] in
                    [
                        "id": p.id, "name": p.name, "version": p.version,
                        "capabilities": p.capabilities, "resourceScopes": p.resourceScopes,
                        "downloadURL": p.downloadURL, "sha256": p.sha256
                    ]
                }
            ]
        }
        return textResult(prettyJSON(["storeCount": stores.count, "stores": stores]))
    }

    func handleResolveOrInstallURL(arguments: [String: Any]) -> [String: Any] {
        let rawURL = arguments["url"] as? String ?? ""
        let shouldInstall = arguments["install"] as? Bool ?? false
        let targetPluginID = arguments["installPluginId"] as? String
        guard !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return textResult("Missing required argument 'url'.", isError: true)
        }

        final class ResultBox: @unchecked Sendable {
            var outcome: Result<[String: Any], Error>?
        }
        let box = ResultBox()
        let sem = DispatchSemaphore(value: 0)
        let supportDir = storeAppSupportDirectory
        let plugsDir = pluginsDirectory

        Task.detached {
            do {
                let resolved = try await PluginStoreSniffer.resolveSource(from: rawURL)
                switch resolved {
                case .storeRegistry(let sub):
                    _ = try PluginStoreService.upsertStore(sub, appSupportDirectory: supportDir)
                    var installedInfo: Any = NSNull()
                    if let targetID = targetPluginID, !targetID.isEmpty {
                        guard let item = sub.manifest.plugins.first(where: { $0.id == targetID }) else {
                            throw LumakeyError.pluginInvalid("商店 '\(sub.manifest.storeName)' 中不存在插件 '\(targetID)'")
                        }
                        let desc = try await PluginStoreService.installStoreItem(item, from: sub, in: plugsDir)
                        installedInfo = ["id": desc.id, "version": desc.manifest.version, "path": desc.directoryURL.path]
                    }
                    box.outcome = .success([
                        "detectedKind": "store",
                        "storeId": sub.id,
                        "storeName": sub.manifest.storeName,
                        "resolvedRegistryURL": sub.resolvedRegistryURL,
                        "pluginCount": sub.manifest.plugins.count,
                        "pluginIDs": sub.manifest.plugins.map(\.id),
                        "installedPlugin": installedInfo
                    ])
                case .singlePlugin(let candidate):
                    var installedPath: Any = NSNull()
                    if shouldInstall {
                        let desc = try PluginStoreService.installSingleCandidate(candidate, in: plugsDir)
                        installedPath = desc.directoryURL.path
                    } else {
                        candidate.cleanupStagingIfNeeded()
                    }
                    box.outcome = .success([
                        "detectedKind": "singlePlugin",
                        "id": candidate.manifest.id,
                        "name": candidate.manifest.name,
                        "version": candidate.manifest.version,
                        "sha256": candidate.sha256,
                        "declaredCapabilities": candidate.manifest.declaredCapabilities.map(\.rawValue),
                        "declaredResourceScopes": candidate.manifest.declaredResourceScopes.map(\.rawValue),
                        "installed": shouldInstall,
                        "installedPath": installedPath
                    ])
                }
            } catch {
                box.outcome = .failure(error)
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 25.0)

        guard let outcome = box.outcome else {
            return textResult("Timed out resolving URL: \(rawURL)", isError: true)
        }
        switch outcome {
        case .success(let dict):
            return textResult(prettyJSON(dict))
        case .failure(let error):
            let msg = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
            return textResult("Resolve/install error: \(msg)", isError: true)
        }
    }
}
