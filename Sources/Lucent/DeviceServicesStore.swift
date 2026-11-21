import Combine
import Foundation
import LucentCore

/// Dedicated observable store for physical mouse smoothing (Mos) and LumaLink remote control state.
/// Isolates high-frequency device/listener status updates from `AppViewModel.objectWillChange`
/// so unrelated overlay, workspace, and settings views avoid unnecessary SwiftUI redraws.
@MainActor
final class DeviceServicesStore: ObservableObject {
    @Published var mosConfig: MosConfig = MosConfig.load()
    @Published var mosTapActive: Bool = false
    @Published var mosAccessibilityTrusted: Bool = false
    @Published var lumaLinkConfig: LumaLinkConfig = LumaLinkConfig.load()
    @Published var lumaLinkStatus: LumaLinkRuntimeSnapshot = LumaLinkRuntimeSnapshot()
    @Published var lumaLinkRdpStatus: LumaLinkRdpStatus = LumaLinkRdpStatus()
}
