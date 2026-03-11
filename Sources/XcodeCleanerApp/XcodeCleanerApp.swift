import AppKit
import SwiftUI

@main
struct XcodeCleanerApp: App {
    @StateObject private var viewModel = InventoryViewModel()
    @NSApplicationDelegateAdaptor(AppLaunchActivationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 920, minHeight: 560)
                .task {
                    viewModel.loadIfNeeded()
                }
        }
    }
}
