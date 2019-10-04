//
//  ViewController.swift
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


import UIKit
import AVFoundation.AVFAudio

// MARK: - ViewController class

/**
 The user interface.
 */
class ViewController: UIViewController {
    
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var voiceIOMeter: LevelMeterView!
    
    @IBAction func recordPressed(_ sender: UIButton) {
        print("Record button pressed.")
        audioEngine?.checkEngineIsRunning()
        audioEngine?.toggleRecording()

        if let isRecording = audioEngine?.isRecording, isRecording {
            sender.setTitle(ButtonTitles.stop.rawValue, for: .normal)
            playButton.isEnabled = false
        } else {
            sender.setTitle(ButtonTitles.record.rawValue, for: .normal)
            playButton.isEnabled = true
        }
    }
    
    @IBAction func playPressed(_ sender: UIButton) {
        print("Play button pressed.")
        audioEngine?.checkEngineIsRunning()
        audioEngine?.togglePlaying()

        if let isPlaying = audioEngine?.isPlaying, isPlaying {
            playButton.setTitle(ButtonTitles.stop.rawValue, for: .normal)
            recordButton.isEnabled = false
        } else {
            playButton.setTitle(ButtonTitles.play.rawValue, for: .normal)
            recordButton.isEnabled = true
        }
    }
    
    private var audioEngine: AudioEngine!

    private enum ButtonTitles: String {
        case record = "Record"
        case play = "Play"
        case stop = "Stop"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupAudioEngine()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handleInterruption(_:)),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handleRouteChange(_:)),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.handleMediaServicesWereReset(_:)),
                                               name: AVAudioSession.mediaServicesWereResetNotification,
                                               object: AVAudioSession.sharedInstance())
    }
    
    func setupAudioSession(sampleRate: Double) {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, options: .defaultToSpeaker)
        } catch {
            print("Could not set audio category: \(error.localizedDescription)")
        }

        do {
            try session.setPreferredSampleRate(sampleRate)
        } catch {
            print("Could not set preferred sample rate: \(error.localizedDescription)")
        }
    }
    
    func setupAudioEngine() {
        do {
            print("Creating audio engine class instance")
            audioEngine = try AudioEngine()

            voiceIOMeter.levelProvider = audioEngine.voiceIOPowerMeter

            print("Setting up audio engine session")
            setupAudioSession(sampleRate: audioEngine.voiceIOFormat.sampleRate)

            print("Setting up audio engine")
            audioEngine.setup()
            
            print("Starting up audio engine session")
            audioEngine.start()
        } catch {
            fatalError("Could not set up audio engine: \(error)")
        }
    }
    
    func resetUIStates() {
        recordButton.setTitle(ButtonTitles.record.rawValue, for: .normal)
        recordButton.isEnabled = true
        playButton.setTitle(ButtonTitles.play.rawValue, for: .normal)
        playButton.isEnabled = false
    }
    
    func resetAudioEngine() {
        audioEngine = nil
    }
    
    @objc
    func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        switch type {
        case .began:
            // Interruption began, take appropriate actions
            
            if let isRecording = audioEngine?.isRecording, isRecording {
                recordButton.setTitle(ButtonTitles.record.rawValue, for: .normal)
            }
            audioEngine?.stopRecordingAndPlayers()
            
            playButton.setTitle(ButtonTitles.record.rawValue, for: .normal)
            playButton.isEnabled = false
        case .ended:
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Could not set audio session active: \(error)")
            }
            
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Interruption Ended - playback should resume
                } else {
                    // Interruption Ended - playback should NOT resume
                }
            }
        @unknown default:
            fatalError("Unknown type: \(type)")
        }
    }
    
    @objc
    func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
            let routeDescription = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
        switch reason {
        case .newDeviceAvailable:
            print("newDeviceAvailable")
        case .oldDeviceUnavailable:
            print("oldDeviceUnavailable")
        case .categoryChange:
            print("categoryChange")
            print("New category: \(AVAudioSession.sharedInstance().category)")
        case .override:
            print("override")
        case .wakeFromSleep:
            print("wakeFromSleep")
        case .noSuitableRouteForCategory:
            print("noSuitableRouteForCategory")
        case .routeConfigurationChange:
            print("routeConfigurationChange")
        case .unknown:
            print("unknown")
        @unknown default:
            fatalError("Really unknown reason: \(reason)")
        }
        
        print("Previous route:\n\(routeDescription)")
        print("Current route:\n\(AVAudioSession.sharedInstance().currentRoute)")
    }
    
    @objc
    func handleMediaServicesWereReset(_ notification: Notification) {
        resetUIStates()
        resetAudioEngine()
        setupAudioEngine()
    }
    
}

