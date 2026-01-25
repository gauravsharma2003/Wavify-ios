//
//  AVAudioUnitDynamicsProcessor.swift
//  Wavify
//
//  Wrapper for Apple's Dynamics Processor Audio Unit (kAudioUnitSubType_DynamicsProcessor)
//  Missing from standard AVFoundation classes.
//

import AVFoundation
import AudioToolbox

/// A wrapper around the Dynamics Processor Audio Unit
public class AVAudioUnitDynamicsProcessor: AVAudioUnitEffect {
    
    public override init() {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        super.init(audioComponentDescription: description)
    }
    
    // MARK: - Parameters
    
    /// Threshold (dB)
    /// Range: -40.0 to 20.0
    public var threshold: Float {
        get {
            var val: Float = 0
            AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, &val)
            return val
        }
        set {
            AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, newValue, 0)
        }
    }
    
    /// Headroom (dB)
    /// Range: 0.1 to 40.0
    public var headRoom: Float {
        get {
            var val: Float = 0
            AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, &val)
            return val
        }
        set {
            AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, newValue, 0)
        }
    }
    
    /// Expansion Ratio
    /// Range: 1.0 to 50.0
    public var expansionRatio: Float {
        get {
            var val: Float = 0
            AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, &val)
            return val
        }
        set {
            AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, newValue, 0)
        }
    }
    
    /// Attack Time (seconds)
    /// Range: 0.0001 to 0.2
    public var attackTime: Float {
        get {
            var val: Float = 0
            AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, &val)
            return val
        }
        set {
            AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, newValue, 0)
        }
    }
    
    /// Release Time (seconds)
    /// Range: 0.01 to 3.0
    public var releaseTime: Float {
        get {
            var val: Float = 0
            AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, &val)
            return val
        }
        set {
            AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, newValue, 0)
        }
    }
    
    /// Master Gain (dB)
    /// Range: -40.0 to 40.0
    public var masterGain: Float {
        get {
            var val: Float = 0
            AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, &val)
            return val
        }
        set {
            AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, newValue, 0)
        }
    }
    
    // Compression Amount (read-only, visualization)
    public var compressionAmount: Float {
        var val: Float = 0
        AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_CompressionAmount, kAudioUnitScope_Global, 0, &val)
        return val
    }
    
    // Input Amplitude (read-only, visualization)
    public var inputAmplitude: Float {
        var val: Float = 0
        AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_InputAmplitude, kAudioUnitScope_Global, 0, &val)
        return val
    }
    
    // Output Amplitude (read-only, visualization)
    public var outputAmplitude: Float {
        var val: Float = 0
        AudioUnitGetParameter(audioUnit, kDynamicsProcessorParam_OutputAmplitude, kAudioUnitScope_Global, 0, &val)
        return val
    }
}
