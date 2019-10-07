//
//  MeterTable.swift
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

// MARK: - MeterTable struct

/**
 Container for processing audio volume.
 */
struct MeterTable {
    
    // MARK: - Variables

    /// The decibel value of the minimum displayed amplitude
    private let kMinDB: Float = -60.0

    // The table needs to be large enough that there are no large gaps in the response
    private let tableSize = 300
    
    private let scaleFactor: Float
    private var meterTable = [Float]()
    
    // MARK: - Methods

    init() {
        let dbResolution = kMinDB / Float(tableSize - 1)
        scaleFactor = 1.0 / dbResolution

        // this controls the curvature of the response.
        // 2.0 is square root, 3.0 is cube root.
        let root: Float = 2.0

        let rroot = 1.0 / root
        let minAmp = dbToAmp(dBValue: kMinDB)
        let ampRange = 1.0 - minAmp
        let invAmpRange = 1.0 / ampRange
        
        for index in 0..<tableSize {
            let decibels = Float(index) * dbResolution
            let amp = dbToAmp(dBValue: decibels)
            let adjAmp = (amp - minAmp) * invAmpRange
            meterTable.append(powf(adjAmp, rroot))
        }
    }
    
    private func dbToAmp(dBValue: Float) -> Float {
        return powf(10.0, 0.05 * dBValue)
    }
    
    func valueForPower(_ power: Float) -> Float {
        if power < kMinDB {
            return 0.0
        } else if power >= 0.0 {
            return 1.0
        } else {
            let index = Int(power) * Int(scaleFactor)
            return meterTable[index]
        }
    }
}
