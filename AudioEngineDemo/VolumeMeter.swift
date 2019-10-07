//
//  VolumeMeter.swift
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


import Foundation
import AVFoundation
import Accelerate


// MARK: - VolumeMeter class

/**
 Compute the audio "power" or volume.
 */
class VolumeMeter: AudioLevelProvider {
    
    // MARK: - Variables

    private let kMinLevel: Float = 0.000_000_01 //-160 dB

    private struct VolumeLevels {
        let average: Float
        let peak: Float
    }

    private var values = [VolumeLevels]()
    
    private var meterTableAvarage = MeterTable()
    private var meterTablePeak = MeterTable()

    var levels: AudioLevels {
        guard !values.isEmpty else { return AudioLevels(level: 0.0, peakLevel: 0.0) }
        return AudioLevels(level: meterTableAvarage.valueForPower(values[0].average),
                           peakLevel: meterTablePeak.valueForPower(values[0].peak))
    }
    
    // MARK: - Methods

    func processSilence() {
        if values.isEmpty { return }
        values = []
    }

    // Calculates average (rms) and peak level of each channel in pcm buffer and caches data
    func process(buffer: AVAudioPCMBuffer) {
        var volumeLevels = [VolumeLevels]()
        let channelCount = Int(buffer.format.channelCount)
        let length = vDSP_Length(buffer.frameLength)

        if let floatData = buffer.floatChannelData {
            for channel in 0..<channelCount {
                volumeLevels.append(calculateVolumes(data: floatData[channel], strideFrames: buffer.stride, length: length))
            }
        } else if let int16Data = buffer.int16ChannelData {
            for channel in 0..<channelCount {
                // convert data from int16 to float values before calculating power values
                var floatChannelData: [Float] = Array(repeating: Float(0.0), count: Int(buffer.frameLength))
                vDSP_vflt16(int16Data[channel], buffer.stride, &floatChannelData, buffer.stride, length)
                var scalar = Float(INT16_MAX)
                vDSP_vsdiv(floatChannelData, buffer.stride, &scalar, &floatChannelData, buffer.stride, length)

                volumeLevels.append(calculateVolumes(data: floatChannelData, strideFrames: buffer.stride, length: length))
            }
        } else if let int32Data = buffer.int32ChannelData {
            for channel in 0..<channelCount {
                // convert data from int32 to float values before calculating power values
                var floatChannelData: [Float] = Array(repeating: Float(0.0), count: Int(buffer.frameLength))
                vDSP_vflt32(int32Data[channel], buffer.stride, &floatChannelData, buffer.stride, length)
                var scalar = Float(INT32_MAX)
                vDSP_vsdiv(floatChannelData, buffer.stride, &scalar, &floatChannelData, buffer.stride, length)

                volumeLevels.append(calculateVolumes(data: floatChannelData, strideFrames: buffer.stride, length: length))
            }
        }
        self.values = volumeLevels
    }

    private func calculateVolumes(data: UnsafePointer<Float>, strideFrames: Int, length: vDSP_Length) -> VolumeLevels {
        var max: Float = 0.0
        vDSP_maxv(data, strideFrames, &max, length)
        if max < kMinLevel {
            max = kMinLevel
        }

        var rms: Float = 0.0
        vDSP_rmsqv(data, strideFrames, &rms, length)
        if rms < kMinLevel {
            rms = kMinLevel
        }

        return VolumeLevels(average: 20.0 * log10(rms), peak: 20.0 * log10(max))
    }
}
