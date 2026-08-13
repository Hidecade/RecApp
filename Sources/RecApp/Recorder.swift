import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum RecordingMode: String, CaseIterable, Identifiable {
    case screen
    case audioOnly

    var id: Self { self }
    var title: String { self == .screen ? "画面録画" : "音声のみ" }
    var systemImage: String { self == .screen ? "display" : "waveform" }
    var menuBarSystemImage: String { self == .screen ? "video" : "waveform" }
    var menuTitle: String { self == .screen ? "画面録画" : "音声録音" }
}

enum AudioFileFormat: String, CaseIterable, Identifiable {
    case m4a
    case wav

    var id: Self { self }
    var title: String { rawValue.uppercased() }
    var contentType: UTType { self == .m4a ? .mpeg4Audio : .wav }
    var fileType: AVFileType { self == .m4a ? .m4a : .wav }
}

@MainActor
final class RecorderViewModel: ObservableObject {
    @Published var displays: [SCDisplay] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var recordingMode: RecordingMode = .screen
    @Published var audioFileFormat: AudioFileFormat = .m4a
    @Published var capturesAudio = true
    @Published var excludesAppAudio = true
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var elapsedText = "00:00"
    @Published var isShowingError = false
    @Published private(set) var errorMessage = ""
    @Published private(set) var canOpenPrivacySettings = false
    @Published private(set) var lastOutputURL: URL?

    private let recorder = ScreenRecorder()
    private var timer: Timer?
    private var startedAt: Date?

    var selectedDisplay: SCDisplay? {
        displays.first { $0.displayID == selectedDisplayID }
    }

    var menuBarTitle: String {
        let mode = recordingMode == .screen ? "画面" : "音声"
        return isRecording ? "\(mode) \(elapsedText)" : mode
    }

    var actionTitle: String {
        switch (recordingMode, isRecording) {
        case (.screen, false): return "録画を開始"
        case (.screen, true): return "録画を停止"
        case (.audioOnly, false): return "録音を開始"
        case (.audioOnly, true): return "録音を停止"
        }
    }

    var statusText: String {
        switch (recordingMode, isRecording) {
        case (.screen, true): return capturesAudio ? "画面と音声を録画中" : "画面を録画中"
        case (.audioOnly, true): return "システム音声を録音中"
        case (.screen, false): return "Macの画面とシステム音声を録画"
        case (.audioOnly, false): return "Macのシステム音声だけを録音"
        }
    }

    func displayName(_ display: SCDisplay, index: Int) -> String {
        let main = display.displayID == CGMainDisplayID() ? "（メイン）" : ""
        return "ディスプレイ \(index + 1) \(display.width)×\(display.height) \(main)"
    }

    func loadDisplays() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays.sorted { $0.displayID < $1.displayID }
            if selectedDisplay == nil {
                selectedDisplayID = displays.first(where: { $0.displayID == CGMainDisplayID() })?.displayID
                    ?? displays.first?.displayID
            }
        } catch {
            show(error, privacyRelated: true)
        }
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func startRecording() async {
        guard let display = selectedDisplay, let outputURL = chooseOutputURL() else { return }
        isBusy = true
        do {
            try await recorder.start(display: display,
                                     outputURL: outputURL,
                                     mode: recordingMode,
                                     audioFileFormat: audioFileFormat,
                                     capturesAudio: recordingMode == .audioOnly || capturesAudio,
                                     excludesAppAudio: excludesAppAudio)
            lastOutputURL = outputURL
            isRecording = true
            startedAt = Date()
            elapsedText = "00:00"
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateElapsed() }
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            show(error, privacyRelated: true)
        }
        isBusy = false
    }

    private func stopRecording() async {
        isBusy = true
        timer?.invalidate()
        timer = nil
        do {
            try await recorder.stop()
            isRecording = false
        } catch {
            isRecording = false
            show(error, privacyRelated: false)
        }
        isBusy = false
    }

    private func chooseOutputURL() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let panel = NSSavePanel()
        panel.title = "録画の保存先"
        let isAudio = recordingMode == .audioOnly
        let fileExtension = isAudio ? audioFileFormat.rawValue : "mp4"
        panel.nameFieldStringValue = "\(isAudio ? "音声収録" : "画面収録") \(formatter.string(from: Date())).\(fileExtension)"
        panel.allowedContentTypes = [isAudio ? audioFileFormat.contentType : .mpeg4Movie]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func updateElapsed() {
        guard let startedAt else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        elapsedText = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func show(_ error: Error, privacyRelated: Bool) {
        errorMessage = privacyRelated
            ? "画面収録の許可が必要です。システム設定の「プライバシーとセキュリティ」→「画面収録とシステムオーディオ」でRecAppを許可してください。\n\n\(error.localizedDescription)"
            : error.localizedDescription
        canOpenPrivacySettings = privacyRelated
        isShowingError = true
    }
}

// All mutable recording state is accessed on writerQueue.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let videoQueue = DispatchQueue(label: "app.recapp.capture.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "app.recapp.capture.audio", qos: .userInitiated)
    private let writerQueue = DispatchQueue(label: "app.recapp.writer", qos: .userInitiated)

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var recordingError: Error?

    func start(display: SCDisplay,
               outputURL: URL,
               mode: RecordingMode,
               audioFileFormat: AudioFileFormat,
               capturesAudio: Bool,
               excludesAppAudio: Bool) async throws {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let currentApplication = shareableContent.applications.first {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let width = even(display.width)
        let height = even(display.height)
        let outputFileType: AVFileType = mode == .audioOnly ? audioFileFormat.fileType : .mp4
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: outputFileType)

        var videoInput: AVAssetWriterInput?
        if mode == .screen {
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: min(24_000_000, width * height * 5),
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoMaxKeyFrameIntervalKey: 120
                ]
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw RecorderError.cannotAddVideo }
            writer.add(input)
            videoInput = input
        }

        var audioInput: AVAssetWriterInput?
        if capturesAudio {
            let audioSettings: [String: Any]
            if mode == .audioOnly && audioFileFormat == .wav {
                audioSettings = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            } else {
                audioSettings = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000
                ]
            }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw RecorderError.cannotAddAudio }
            writer.add(input)
            audioInput = input
        }
        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotStartWriter }

        let filter: SCContentFilter
        if let currentApplication {
            filter = SCContentFilter(display: display,
                                     excludingApplications: [currentApplication],
                                     exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = capturesAudio
        configuration.excludesCurrentProcessAudio = excludesAppAudio
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        sessionStarted = false
        recordingError = nil

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        if mode == .screen {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        }
        if capturesAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        try await stream.startCapture()
    }

    func stop() async throws {
        if let stream {
            try await stream.stopCapture()
        }
        self.stream = nil

        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            writerQueue.async { [self] in
                videoInput?.markAsFinished()
                audioInput?.markAsFinished()
                guard let writer else {
                    continuation.resume(returning: .failure(RecorderError.noWriter))
                    return
                }
                if sessionStarted {
                    writer.finishWriting { [self] in
                        let error = recordingError ?? writer.error
                        clearWriter()
                        continuation.resume(returning: error.map(Result.failure) ?? .success(()))
                    }
                } else {
                    writer.cancelWriting()
                    clearWriter()
                    continuation.resume(returning: .failure(RecorderError.noFrames))
                }
            }
        }
        try result.get()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        writerQueue.async { [weak self] in self?.recordingError = error }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        if type == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: statusRaw) == .complete else { return }
        }

        writerQueue.async { [weak self] in
            guard let self, let writer = self.writer, writer.status == .writing else { return }
            if !self.sessionStarted {
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                self.sessionStarted = true
            }
            let input = type == .screen ? self.videoInput : self.audioInput
            if let input, input.isReadyForMoreMediaData, !input.append(sampleBuffer) {
                self.recordingError = writer.error ?? RecorderError.appendFailed
            }
        }
    }

    private func even(_ value: Int) -> Int { value - value % 2 }

    private func clearWriter() {
        writer = nil
        videoInput = nil
        audioInput = nil
        sessionStarted = false
    }
}

private enum RecorderError: LocalizedError {
    case cannotAddVideo, cannotAddAudio, cannotStartWriter, appendFailed, noWriter, noFrames

    var errorDescription: String? {
        switch self {
        case .cannotAddVideo: return "映像エンコーダーを準備できませんでした。"
        case .cannotAddAudio: return "音声エンコーダーを準備できませんでした。"
        case .cannotStartWriter: return "出力ファイルへの書き込みを開始できませんでした。"
        case .appendFailed: return "録画データの書き込みに失敗しました。"
        case .noWriter: return "録画セッションが見つかりません。"
        case .noFrames: return "録画フレームを取得できませんでした。"
        }
    }
}
