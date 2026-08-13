import AppKit
import SwiftUI

@main
struct RecApp: App {
    @StateObject private var model = RecorderViewModel()

    var body: some Scene {
        WindowGroup {
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
            if model.isRecording {
                Text("録画中  \(model.elapsedText)")
            } else {
                Text(model.recordingMode.title)
            }

            Divider()

            Button(model.isRecording ? "録画を停止" : "録画を開始") {
                Task { await model.toggleRecording() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.isBusy || (!model.isRecording && model.selectedDisplay == nil))

            Divider()

            Button("RecAppを表示") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
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
        } label: {
            Image(systemName: model.isRecording ? "stop.circle.fill" : "record.circle")
                .symbolRenderingMode(.monochrome)
        }
    }
}
