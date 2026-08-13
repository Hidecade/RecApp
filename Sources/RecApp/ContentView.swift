import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: RecorderViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            settings
            Spacer(minLength: 24)
            controls
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(FloatingWindowConfigurator())
        .task { await model.loadDisplays() }
        .alert("録画できませんでした", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) { }
            if model.canOpenPrivacySettings {
                Button("設定を開く") { model.openPrivacySettings() }
            }
        } message: {
            Text(model.errorMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isRecording ? "record.circle.fill" : model.recordingMode.systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(model.isRecording ? .red : .primary)
                .symbolEffect(.pulse, isActive: model.isRecording)
            VStack(alignment: .leading, spacing: 3) {
                Text("RecApp")
                    .font(.headline.weight(.semibold))
                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRecording {
                Text(model.elapsedText)
                    .font(.system(.title3, design: .monospaced, weight: .medium))
                    .contentTransition(.numericText())
            }
        }
        .padding(18)
    }

    private var settings: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 13) {
            GridRow {
                Label("録画モード", systemImage: "record.circle")
                Picker("録画モード", selection: $model.recordingMode) {
                    ForEach(RecordingMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.isRecording || model.isBusy)
                .onChange(of: model.recordingMode) { _, mode in
                    if mode == .audioOnly { model.capturesAudio = true }
                }
            }
            GridRow {
                Label("録画する画面", systemImage: "rectangle.on.rectangle")
                Picker("録画する画面", selection: $model.selectedDisplayID) {
                    if model.displays.isEmpty {
                        Text("画面を読み込み中…").tag(CGDirectDisplayID?.none)
                    }
                    ForEach(Array(model.displays.enumerated()), id: \.element.displayID) { index, display in
                        Text(model.displayName(display, index: index)).tag(Optional(display.displayID))
                    }
                }
                .labelsHidden()
                .disabled(model.recordingMode == .audioOnly || model.isRecording || model.isBusy)
            }
            GridRow {
                Label("システム音声", systemImage: "speaker.wave.2")
                Toggle(model.recordingMode == .audioOnly ? "システム音声を録音" : "システム音声を含める",
                       isOn: $model.capturesAudio)
                    .toggleStyle(.switch)
                    .disabled(model.recordingMode == .audioOnly || model.isRecording || model.isBusy)
            }
            if model.recordingMode == .audioOnly {
                GridRow {
                    Label("保存形式", systemImage: "waveform")
                    Picker("保存形式", selection: $model.audioFileFormat) {
                        ForEach(AudioFileFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(model.isRecording || model.isBusy)
                }
            }
            GridRow {
                Label("このアプリの音", systemImage: "speaker.slash")
                Toggle("RecAppの音声を除外", isOn: $model.excludesAppAudio)
                    .toggleStyle(.switch)
                    .disabled(!model.capturesAudio || model.isRecording || model.isBusy)
            }
            if let outputURL = model.lastOutputURL, !model.isRecording {
                GridRow {
                    Label("前回の録画", systemImage: "film")
                    Button(outputURL.lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                    .buttonStyle(.link)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var controls: some View {
        HStack {
            if !model.isRecording {
                Button {
                    Task { await model.loadDisplays() }
                } label: {
                    Label("画面を再読み込み", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
            }
            Spacer()
            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label(model.isRecording ? (model.recordingMode == .audioOnly ? "録音を停止" : "録画を停止") : model.actionTitle,
                      systemImage: model.isRecording ? "stop.fill" : "record.circle")
                    .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isRecording ? .red : .accentColor)
            .controlSize(.large)
            .disabled(model.isBusy || (!model.isRecording && model.selectedDisplay == nil))
        }
        .padding(18)
    }
}

private struct FloatingWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.level = .floating
        window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.hidesOnDeactivate = false
    }
}
