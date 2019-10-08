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
    
    // MARK: - Variables
    
    /// Number of microphone channels: mono = 1, stereo = 2.
    let nChannels: AVAudioChannelCount = 1
    let nBuffer: AVAudioFrameCount = 256
    
    /// Either request a sample rate here (which must be consistent with the hardware rate, e.g., 48_000), or leave unset (nil) in which case the hardware rate is auto-detected. The latter doesn't work well on simulators.
    let desiredSampleRate: Double? = 48_000 // 48_000

    private var recordedFileURL = URL( fileURLWithPath: "AudioEngineDemoRecording.caf",
                                       isDirectory: false,
                                       relativeTo: URL(fileURLWithPath: NSTemporaryDirectory()) )
    private var recordedFilePlayer = AVAudioPlayerNode()
    private var avAudioEngine = AVAudioEngine()
    private var haveNewRecording = false
    private var recordedFile: AVAudioFile?

    public private(set) var audioFormat: AVAudioFormat
    public private(set) var isRecording = false
    public private(set) var volumeMeter = VolumeMeter()

    private enum AudioEngineError: Error {
        case bufferRetrieveError
        case audioFormatError
        case audioFileNotFound
    }
    
    /**
     Query if playback is happening.
     */
    var isPlaying: Bool {
        return recordedFilePlayer.isPlaying
    }


    // MARK: - Methods
    /**
     Initialize through doing the following:
     - Get the audio capture hardware rate.
     - Set the voice I/O sample rate to this rate, unless another is specified.
     - Similarly set file format sample rate.
     - Also set number of channels (probably overriding stereo).
     
     - Throws: `AudioEngineError.audioFormatError` if `AVAudioFormat` cannot be set as needed.
     */
    init() throws {
        avAudioEngine.attach(recordedFilePlayer)
        print("Record file URL: \(recordedFileURL.absoluteString)")
        
        // Figure out a sample rate & number of audio channels
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

        // Set the audio mic input & speaker output & file parameters
        // Must be non-interleaved.
        guard let tempAudioFormat = AVAudioFormat( commonFormat: .pcmFormatFloat32,
                                                   sampleRate: sampleRate,
                                                   channels: nChannels,
                                                   interleaved: false )
            else { throw AudioEngineError.audioFormatError }
        audioFormat = tempAudioFormat
        print("Audio format: \(String(describing: audioFormat))")
    }

    /**
     Connect up the voice input, mixer and voice output nodes, and install a mic tap, then prep the `AVAudioEngine`.
     */
    func setupEngine() {
        let input = avAudioEngine.inputNode
        let mixer = avAudioEngine.mainMixerNode
        let output = avAudioEngine.outputNode

        print("Connecting recorded file player")
        avAudioEngine.connect(recordedFilePlayer, to: mixer, format: audioFormat)

        print("Connecting mixer")
        avAudioEngine.connect(mixer, to: output, format: audioFormat)

        print("Installing mic tap")
        input.installTap(onBus: 0, bufferSize: nBuffer, format: audioFormat) { buffer, timeStamp in
            if self.isRecording {
                do {
                    print("Writing to file: \(buffer), \(timeStamp)")
                    try self.recordedFile?.write(from: buffer)
                } catch {
                    print("Could not write buffer: \(error)")
                }
                self.volumeMeter.process(buffer: buffer)
            } else {
                self.volumeMeter.processSilence()
            }
        }
        print("Prepping audio engine")
        avAudioEngine.prepare()
    }

    /**
     Start the `AVAudioEngine`.
     */
    func startEngine() {
        do {
            try avAudioEngine.start()
        } catch {
            print("startEngine: Could not startEngine audio engine: \(error)")
        }
    }

    /**
     Check that `AVAudioEngine` is running.
     */
    func checkEngineIsRunning() {
        if !avAudioEngine.isRunning {
            startEngine()
        }
    }

    /**
     Turn on or off the recording of audio to a file.
     */
    func toggleRecording() {
        if isRecording {
            isRecording = false
        } else {
            recordedFilePlayer.stop()
            do {
                recordedFile = try AVAudioFile(forWriting: recordedFileURL, settings: audioFormat.settings)
                haveNewRecording = true
                isRecording = true
            } catch {
                print("Could not create file for recording: \(error)")
            }
        }
    }

    /**
     Explicitly stop audio file playback and flag to stop recording.
     */
    func stopRecordingAndPlayers() {
        if isRecording {
            isRecording = false
        }
        recordedFilePlayer.stop()
    }
    
    /**
     Turn audio playback on or off (by pausing it).
     */
    func togglePlaying() {
        if recordedFilePlayer.isPlaying {
            recordedFilePlayer.pause()
        } else {
            if haveNewRecording {
                guard let recordedBuffer = AudioEngine.fetchFileIntoBuffer(fileURL: recordedFileURL) else { return }
                print("togglePlaying: buffer length = \(recordedBuffer.frameLength), buffer capacity = \(recordedBuffer.frameCapacity), format = \(recordedBuffer.format)")
                recordedFilePlayer.scheduleBuffer(recordedBuffer, at: nil, options: .loops)
                haveNewRecording = false
            }
            recordedFilePlayer.play()
        }
    }
    
    /**
     Get audio file and put into `AVAudioPCMBuffer` so we can play it back.
     
     - Parameter fileURL: Internal "path" to temporary audio file.
     
     - Returns: `AVAudioPCMBuffer` filled with the temp file audio data, or `nil` if failure.
     */
    static func fetchFileIntoBuffer( fileURL: URL ) -> AVAudioPCMBuffer? {
        let file: AVAudioFile!
        do {
            try file = AVAudioFile( forReading: fileURL )
        } catch {
            print("fetchFileIntoBuffer: Could not load file: \(error)")
            return nil
        }
        file.framePosition = 0
        print("fetchFileIntoBuffer: \(file.fileFormat)  length = \(file.length)")

        guard let buffer = AVAudioPCMBuffer( pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length) )
            else { return nil }
        do {
            try file.read(into: buffer)
        } catch {
            print("fetchFileIntoBuffer: Could not load file into buffer: \(error)")
            return nil
        }
        file.framePosition = 0
        return buffer
    }
}
