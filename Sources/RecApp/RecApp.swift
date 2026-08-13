import AppKit
import SwiftUI

@main
struct RecApp: App {
    @StateObject private var model = RecorderViewModel()

    var body: some Scene {
        WindowGroup("RecApp", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 420, maxWidth: 420, minHeight: 350)
        }
        .defaultSize(width: 420, height: 390)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("録画") {
                Button(model.isRecording ? "録画を停止" : "録画を開始") {
                    Task { await model.toggleRecording() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.isBusy || (!model.isRecording && model.selectedDisplay == nil))
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label(model.menuBarTitle,
                  systemImage: model.isRecording ? "stop.circle.fill" : model.recordingMode.menuBarSystemImage)
                .symbolRenderingMode(.monochrome)
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: RecorderViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.isRecording ? "\(model.recordingMode.menuTitle)を記録中  \(model.elapsedText)" : model.recordingMode.menuTitle)

        Divider()

        Button(model.isRecording ? "録画を停止" : "録画を開始") {
            Task { await model.toggleRecording() }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(model.isBusy || (!model.isRecording && model.selectedDisplay == nil))

        Divider()

        Button("RecAppを表示") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("RecAppを終了") {
            Task {
                if model.isRecording {
                    await model.toggleRecording()
                }
                NSApp.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }
}
