//
//  AudioEngine.swift
//  AudioEngineDemo
//
//  Modified by Colin Stark on 2019/10/02.
//  Copyright © 2019 Bluemarblesoft. All rights reserved.
//
//  Based on:
//    https://developer.apple.com/documentation/avfoundation/audio_track_engineering/using_voice_processing
//  See LICENSE folder for licensing information about this source material.
//  Note that all audio files have been removed.
//  Copyright © 2019 Apple. All rights reserved.
//


import AVFoundation
import Foundation

// MARK: - AudioEngine class

/**
 Demo of how to use`AVAudioEngine` to:
    - acquire microphone audio on an iOS device using a tap
    - write audio to a temporary file
    - replay the audio.
 
 Deployment works on iOS 12.4 and 13+. However, behavior is different on each: for 13+, sample rates cannot be varied beyond 48kHz without causing runtime errors.
 
 This is a stripped down version of a demo (illustrating new voice processing capabilitiers in iOS 13) provided by Apple at:
 https://developer.apple.com/documentation/avfoundation/audio_track_engineering/using_voice_processing
 
 */
class AudioEngine {
    
    let nMicChannels: AVAudioChannelCount = 2
    let nMicTapBuffer: AVAudioFrameCount = 256
    
    /// Either request a sample rate here (which must be consistent with the hardware rate, e.g., 48_000), or leave unset (nil) in which case the hardware rate is auto-detected. The latter doesn't work well on simulators.
    let desiredSampleRate: Double? = 48_000 // 48_000

    private var recordedFileURL = URL( fileURLWithPath: "AudioEngineDemoRecording.caf",
                                       isDirectory: false,
                                       relativeTo: URL(fileURLWithPath: NSTemporaryDirectory()) )
    private var recordedFilePlayer = AVAudioPlayerNode()
    private var avAudioEngine = AVAudioEngine()
    private var isNewRecordingAvailable = false
    private var fileFormat: AVAudioFormat
    private var recordedFile: AVAudioFile?

    public private(set) var voiceIOFormat: AVAudioFormat
    public private(set) var isRecording = false
    public private(set) var voiceIOPowerMeter = PowerMeter()

    private enum AudioEngineError: Error {
        case bufferRetrieveError
        case fileFormatError
        case audioFileNotFound
    }

    init() throws {
        avAudioEngine.attach(recordedFilePlayer)
        print("Record file URL: \(recordedFileURL.absoluteString)")
        
        let hwSampleRate = AVAudioSession.sharedInstance().sampleRate
        let sampleRate: Double
        if desiredSampleRate != nil {
            sampleRate = desiredSampleRate!
        } else {
            sampleRate = hwSampleRate
        }
        print( "Hardware sample rate = \(hwSampleRate)" )
        print( "Specified sample rate = \(String(describing: desiredSampleRate)) => \(hwSampleRate)" )
        print( "Number of audio channels = \(AVAudioSession.sharedInstance().inputNumberOfChannels)" )

        guard let tempvoiceIOFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                    sampleRate: sampleRate,
                                                    channels: nMicChannels,
                                                    interleaved: false)
            else { throw AudioEngineError.fileFormatError }
        voiceIOFormat = tempvoiceIOFormat
        print("Voice IO format: \(String(describing: voiceIOFormat))")
        
        // Audio files _must_ be interleaved
        guard let tempFileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                 sampleRate: sampleRate,
                                                 channels: nMicChannels,
                                                 interleaved: true)
            else { throw AudioEngineError.fileFormatError }
        fileFormat = tempFileFormat
        print("File format: \(String(describing: fileFormat))")

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(configChanged(_:)),
                                               name: .AVAudioEngineConfigurationChange,
                                               object: avAudioEngine)
        print("Added observer to monitor any change in config")
    }

    @objc
    private func configChanged(_ notification: Notification) {
        checkEngineIsRunning()
    }

    static func getBuffer(fileURL: URL) -> AVAudioPCMBuffer? {
        let file: AVAudioFile!
        do {
            try file = AVAudioFile(forReading: fileURL)
        } catch {
            print("getBuffer: Could not load file: \(error)")
            return nil
        }
        file.framePosition = 0
        print("getBuffer: \(file.fileFormat)  length = \(file.length)")

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            print("getBuffer: Could not load file into buffer: \(error)")
            return nil
        }
        file.framePosition = 0
        return buffer
    }

    func setup() {
        let input = avAudioEngine.inputNode
        let mixer = avAudioEngine.mainMixerNode
        let output = avAudioEngine.outputNode

        print("Connecting recorded file player")
        avAudioEngine.connect(recordedFilePlayer, to: mixer, format: voiceIOFormat)

        print("Connecting mixer")
        avAudioEngine.connect(mixer, to: output, format: voiceIOFormat)

        print("Installing mic tap")
        input.installTap(onBus: 0, bufferSize: nMicTapBuffer, format: voiceIOFormat) { buffer, timeStamp in
            if self.isRecording {
                do {
                    print("Writing to file: \(buffer), \(timeStamp)")
                    try self.recordedFile?.write(from: buffer)
                } catch {
                    print("Could not write buffer: \(error)")
                }
                self.voiceIOPowerMeter.process(buffer: buffer)
            } else {
                self.voiceIOPowerMeter.processSilence()
            }
        }
        
        print("Prepping audio engine")
        avAudioEngine.prepare()
    }

    func start() {
        do {
            try avAudioEngine.start()
        } catch {
            print("start: Could not start audio engine: \(error)")
        }
    }

    func checkEngineIsRunning() {
        if !avAudioEngine.isRunning {
            start()
        }
    }

    func toggleRecording() {
        if isRecording {
            isRecording = false
        } else {
            recordedFilePlayer.stop()
            do {
                recordedFile = try AVAudioFile(forWriting: recordedFileURL, settings: fileFormat.settings)
                isNewRecordingAvailable = true
                isRecording = true
            } catch {
                print("Could not create file for recording: \(error)")
            }
        }
    }

    func stopRecordingAndPlayers() {
        if isRecording {
            isRecording = false
        }
        recordedFilePlayer.stop()
    }

    var isPlaying: Bool {
        return recordedFilePlayer.isPlaying
    }

    func togglePlaying() {
        if recordedFilePlayer.isPlaying {
            recordedFilePlayer.pause()
        } else {
            if isNewRecordingAvailable {
                guard let recordedBuffer = AudioEngine.getBuffer(fileURL: recordedFileURL) else { return }
                print("togglePlaying: length = \(recordedBuffer.frameLength), capacity = \(recordedBuffer.frameCapacity), \(recordedBuffer.format)")
                recordedFilePlayer.scheduleBuffer(recordedBuffer, at: nil, options: .loops)
                isNewRecordingAvailable = false
            }
            recordedFilePlayer.play()
        }
    }
}
