import SwiftUI

@main
struct OptimizrApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1_080, minHeight: 720)
                .tint(Palette.memory)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_260, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Scan This Mac") {
                    model.scan()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isScanning)

                Button("Export Report…") {
                    model.exportReport()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.hasScanned)
            }
        }
    }
}
