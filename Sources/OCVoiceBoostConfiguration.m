//
//  OCVoiceBoostConfiguration.m
//  YTLiteSkipSilence
//

#import "OCVoiceBoostConfiguration.h"
#import "OCLog.h"

@implementation OCVoiceBoostConfiguration

+ (instancetype)standardConfiguration {
    OCVoiceBoostConfiguration *c = [[self alloc] initWithTargetLUFS:-16
                                                compressorThreshold:-24.0f
                                                   deEsserThreshold:-30.0f
                                                         masterGain:3.0f
                                                  isStandardPreset:YES];
    return c;
}

+ (instancetype)configurationWithTargetLUFS:(NSInteger)lufs
                         compressorThreshold:(float)compressor
                            deEsserThreshold:(float)deEsser
                                  masterGain:(float)gain {
    return [[self alloc] initWithTargetLUFS:lufs
                         compressorThreshold:compressor
                            deEsserThreshold:deEsser
                                  masterGain:gain
                           isStandardPreset:NO];
}

- (instancetype)initWithTargetLUFS:(NSInteger)lufs
                compressorThreshold:(float)compressor
                   deEsserThreshold:(float)deEsser
                         masterGain:(float)gain
                  isStandardPreset:(BOOL)standard {
    if ((self = [super init])) {
        _targetLUFS           = lufs;
        _compressorThreshold  = compressor;
        _deEsserThreshold     = deEsser;
        _masterGainDB         = gain;
        _isStandardPreset     = standard;
    }
    return self;
}

- (nullable AVAudioMixerNode *)applyToEngine:(AVAudioEngine *)engine
                                  sourceNode:(AVAudioNode *)sourceNode {
    if (!engine || !sourceNode) return nil;

    // Build the voice-boost effect chain:
    //   source -> AVAudioUnitEQ (de-esser + high shelf) -> AVAudioUnit
    //   Compressor -> master gain (via EQ) -> engine's mainMixerNode
    AVAudioUnitEQ       *eq         = [[AVAudioUnitEQ alloc] initWithNumberOfBands:3];
    AVAudioUnitEffect   *compressor = [self makeCompressorWithEngine:engine];
    AVAudioUnitEQ       *masterEQ   = [[AVAudioUnitEQ alloc] initWithNumberOfBands:1];

    if (!eq || !compressor || !masterEQ) {
        OCLogW(VoiceBoost, @"failed to build voice-boost chain");
        return nil;
    }

    // Band 0: high-shelf boost for voice intelligibility.
    AVAudioUnitEQFilterParameters *hi = eq.bands[0];
    hi.filterType   = AVAudioUnitEQFilterTypeHighShelf;
    hi.frequency    = 3500.0;
    hi.gain         = 4.0;
    hi.bypass       = NO;

    // Band 1: parametric peaking at 6 kHz for clarity.
    AVAudioUnitEQFilterParameters *pk = eq.bands[1];
    pk.filterType   = AVAudioUnitEQFilterTypeParametric;
    pk.frequency    = 6000.0;
    pk.bandwidth    = 1.0;
    pk.gain         = 2.0;
    pk.bypass       = NO;

    // Band 2: high-pass at 80 Hz to kill rumble.
    AVAudioUnitEQFilterParameters *hp = eq.bands[2];
    hp.filterType   = AVAudioUnitEQFilterTypeHighPass;
    hp.frequency    = 80.0;
    hp.bypass       = NO;

    // Compressor configuration from Overcast defaults.
    AudioUnitParameterSet(compressor.audioUnit, kAudioUnitScope_Global, 0,
                          kDynamicsProcessorParamThreshold, _compressorThreshold);
    AudioUnitParameterSet(compressor.audioUnit, kAudioUnitScope_Global, 0,
                          kDynamicsProcessorParamAttack, 0.005);
    AudioUnitParameterSet(compressor.audioUnit, kAudioUnitScope_Global, 0,
                          kDynamicsProcessorParamRelease, 0.05);

    // Master gain.
    AVAudioUnitEQFilterParameters *mg = masterEQ.bands[0];
    mg.filterType   = AVAudioUnitEQFilterTypeParametric;
    mg.frequency    = 1000.0;
    mg.bandwidth    = 5.0;
    mg.gain         = _masterGainDB;
    mg.bypass       = NO;

    [engine attachNode: eq];
    [engine attachNode: compressor];
    [engine attachNode: masterEQ];

    [engine connect: sourceNode  to: eq         format: nil];
    [engine connect: eq          to: compressor format: nil];
    [engine connect: compressor  to: masterEQ   format: nil];
    [engine connect: masterEQ    to: engine.mainMixerNode format: nil];

    OCLogI(VoiceBoost, @"voice boost applied: targetLUFS=%ld comp=%.1f deEss=%.1f gain=%.1f",
           (long)_targetLUFS, _compressorThreshold, _deEsserThreshold, _masterGainDB);

    return engine.mainMixerNode;
}

- (AVAudioUnitEffect *)makeCompressorWithEngine:(AVAudioEngine *)engine {
    AudioComponentDescription comp = {0};
    comp.componentType         = kAudioUnitType_Effect;
    comp.componentSubType      = kAudioUnitSubType_DynamicsProcessor;
    comp.componentManufacturer = kAudioUnitManufacturer_Apple;
    return [[AVAudioUnitEffect alloc] initWithAudioComponentDescription:comp];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithTargetLUFS:_targetLUFS
                                              compressorThreshold:_compressorThreshold
                                                 deEsserThreshold:_deEsserThreshold
                                                       masterGain:_masterGainDB
                                                isStandardPreset:_isStandardPreset];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeInteger:_targetLUFS forKey:@"targetLUFS"];
    [c encodeFloat:_compressorThreshold forKey:@"compressorThreshold"];
    [c encodeFloat:_deEsserThreshold forKey:@"deEsserThreshold"];
    [c encodeFloat:_masterGainDB forKey:@"masterGainDB"];
    [c encodeBool:_isStandardPreset forKey:@"isStandardPreset"];
}

- (instancetype)initWithCoder:(NSCoder *)c {
    return [self initWithTargetLUFS:[c decodeIntegerForKey:@"targetLUFS"]
                compressorThreshold:[c decodeFloatForKey:@"compressorThreshold"]
                   deEsserThreshold:[c decodeFloatForKey:@"deEsserThreshold"]
                         masterGain:[c decodeFloatForKey:@"masterGainDB"]
                  isStandardPreset:[c decodeBoolForKey:@"isStandardPreset"]];
}

- (NSString *)description {
    return [NSString stringWithFormat:
        @"<OCVoiceBoostConfiguration targetLUFS=%ld comp=%.1f deEss=%.1f gain=%.1f standard=%@>",
        (long)_targetLUFS, _compressorThreshold, _deEsserThreshold, _masterGainDB,
        _isStandardPreset ? @"YES" : @"NO"];
}

@end
