//
//  Voice.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation

// MARK: - Voice Provider

/// TTS engine that generates speech.
enum VoiceProvider: String, Codable, Sendable, CaseIterable {
    /// iOS AVSpeechSynthesizer - always available fallback
    case system
    /// Kokoro CoreML - high-quality on-device
    case kokoro
    /// Qwen DashScope API - cloud with voice cloning
    case qwenCloud
    
    var requiresNetwork: Bool {
        self == .qwenCloud
    }
    
    var supportsVoiceCloning: Bool {
        self == .qwenCloud
    }
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .kokoro: return "Kokoro"
        case .qwenCloud: return "Cloud"
        }
    }
}

// MARK: - Voice Category

/// Classification of voices by origin.
enum VoiceCategory: String, Codable, Sendable, CaseIterable {
    case system
    case preset
    case cloned
    case designed
    
    var displayName: String {
        switch self {
        case .system: return "System Voices"
        case .preset: return "Premium Voices"
        case .cloned: return "My Voice"
        case .designed: return "Custom Voices"
        }
    }
    
    var iconName: String {
        switch self {
        case .system: return "speaker.wave.2.fill"
        case .preset: return "waveform"
        case .cloned: return "person.wave.2.fill"
        case .designed: return "sparkles"
        }
    }
}

// MARK: - Voice Gender

enum VoiceGender: String, Codable, Sendable, CaseIterable {
    case female
    case male
    case neutral
    
    var displayName: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .neutral: return "Neutral"
        }
    }
}

// MARK: - Voice

/// A text-to-speech voice configuration.
struct Voice: Identifiable, Codable, Hashable, Sendable {
    
    let id: String
    let name: String
    let provider: VoiceProvider
    let category: VoiceCategory
    let languageCode: String
    let isPremiumOnly: Bool
    
    // Provider-specific identifiers
    let kokoroVoiceId: String?
    let qwenSpeakerId: String?
    let systemVoiceId: String?
    
    // Clone metadata
    let isCloned: Bool
    let cloneSourceAudioURL: URL?
    let clonedAt: Date?
    
    // Characteristics
    let gender: VoiceGender?
    let style: String?
    let previewAudioURL: URL?
    
    init(
        id: String,
        name: String,
        provider: VoiceProvider,
        category: VoiceCategory,
        languageCode: String,
        isPremiumOnly: Bool = false,
        kokoroVoiceId: String? = nil,
        qwenSpeakerId: String? = nil,
        systemVoiceId: String? = nil,
        isCloned: Bool = false,
        cloneSourceAudioURL: URL? = nil,
        clonedAt: Date? = nil,
        gender: VoiceGender? = nil,
        style: String? = nil,
        previewAudioURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.category = category
        self.languageCode = languageCode
        self.isPremiumOnly = isPremiumOnly
        self.kokoroVoiceId = kokoroVoiceId
        self.qwenSpeakerId = qwenSpeakerId
        self.systemVoiceId = systemVoiceId
        self.isCloned = isCloned
        self.cloneSourceAudioURL = cloneSourceAudioURL
        self.clonedAt = clonedAt
        self.gender = gender
        self.style = style
        self.previewAudioURL = previewAudioURL
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Voice, rhs: Voice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Access Control

extension Voice {
    
    func isAccessible(for tier: SubscriptionTier) -> Bool {
        isPremiumOnly ? tier.hasPremiumAccess : true
    }
    
    var requiredTier: SubscriptionTier {
        isPremiumOnly ? .premium : .free
    }
}

// MARK: - Factory Methods

extension Voice {
    
    static func systemVoice(identifier: String, name: String, languageCode: String) -> Voice {
        Voice(
            id: "system_\(identifier)",
            name: name,
            provider: .system,
            category: .system,
            languageCode: languageCode,
            systemVoiceId: identifier
        )
    }
    
    static func kokoroVoice(
        id voiceId: String,
        name: String,
        languageCode: String = "en-US",
        isPremiumOnly: Bool = true,
        gender: VoiceGender? = nil,
        style: String? = nil
    ) -> Voice {
        Voice(
            id: "kokoro_\(voiceId)",
            name: name,
            provider: .kokoro,
            category: .preset,
            languageCode: languageCode,
            isPremiumOnly: isPremiumOnly,
            kokoroVoiceId: voiceId,
            gender: gender,
            style: style
        )
    }
    
    static func qwenVoice(
        speakerId: String,
        name: String,
        languageCode: String = "en-US",
        gender: VoiceGender? = nil,
        style: String? = nil
    ) -> Voice {
        Voice(
            id: "qwen_\(speakerId)",
            name: name,
            provider: .qwenCloud,
            category: .preset,
            languageCode: languageCode,
            isPremiumOnly: true,
            qwenSpeakerId: speakerId,
            gender: gender,
            style: style
        )
    }
    
    static func clonedVoice(
        cloneId: String,
        name: String = "My Voice",
        sourceURL: URL,
        qwenSpeakerId: String,
        languageCode: String = "en-US"
    ) -> Voice {
        Voice(
            id: "qwen_clone_\(cloneId)",
            name: name,
            provider: .qwenCloud,
            category: .cloned,
            languageCode: languageCode,
            isPremiumOnly: true,
            qwenSpeakerId: qwenSpeakerId,
            isCloned: true,
            cloneSourceAudioURL: sourceURL,
            clonedAt: Date()
        )
    }
    
    static func designedVoice(
        designId: String,
        name: String,
        qwenSpeakerId: String,
        languageCode: String = "en-US",
        style: String
    ) -> Voice {
        Voice(
            id: "qwen_design_\(designId)",
            name: name,
            provider: .qwenCloud,
            category: .designed,
            languageCode: languageCode,
            isPremiumOnly: true,
            qwenSpeakerId: qwenSpeakerId,
            style: style
        )
    }
}

// MARK: - Preset Voice Catalogs

extension Voice {
    
    /// Free Kokoro voices (6 curated)
    static let freeKokoroVoices: [Voice] = [
        .kokoroVoice(id: "af_heart", name: "Heart", isPremiumOnly: false, gender: .female, style: "warm"),
        .kokoroVoice(id: "af_bella", name: "Bella", isPremiumOnly: false, gender: .female, style: "friendly"),
        .kokoroVoice(id: "am_adam", name: "Adam", isPremiumOnly: false, gender: .male, style: "confident"),
        .kokoroVoice(id: "am_michael", name: "Michael", isPremiumOnly: false, gender: .male, style: "professional"),
        .kokoroVoice(id: "bf_emma", name: "Emma", languageCode: "en-GB", isPremiumOnly: false, gender: .female, style: "British"),
        .kokoroVoice(id: "bm_george", name: "George", languageCode: "en-GB", isPremiumOnly: false, gender: .male, style: "British")
    ]
    
    /// Premium Kokoro voices (48 additional)
    static let premiumKokoroVoices: [Voice] = [
        // American Female
        .kokoroVoice(id: "af_alloy", name: "Alloy", gender: .female, style: "neutral"),
        .kokoroVoice(id: "af_aoede", name: "Aoede", gender: .female, style: "melodic"),
        .kokoroVoice(id: "af_jessica", name: "Jessica", gender: .female, style: "casual"),
        .kokoroVoice(id: "af_kore", name: "Kore", gender: .female, style: "youthful"),
        .kokoroVoice(id: "af_nicole", name: "Nicole", gender: .female, style: "professional"),
        .kokoroVoice(id: "af_nova", name: "Nova", gender: .female, style: "energetic"),
        .kokoroVoice(id: "af_river", name: "River", gender: .female, style: "calm"),
        .kokoroVoice(id: "af_sarah", name: "Sarah", gender: .female, style: "friendly"),
        .kokoroVoice(id: "af_sky", name: "Sky", gender: .female, style: "airy"),
        
        // American Male
        .kokoroVoice(id: "am_echo", name: "Echo", gender: .male, style: "resonant"),
        .kokoroVoice(id: "am_eric", name: "Eric", gender: .male, style: "authoritative"),
        .kokoroVoice(id: "am_fenrir", name: "Fenrir", gender: .male, style: "deep"),
        .kokoroVoice(id: "am_liam", name: "Liam", gender: .male, style: "friendly"),
        .kokoroVoice(id: "am_onyx", name: "Onyx", gender: .male, style: "smooth"),
        .kokoroVoice(id: "am_puck", name: "Puck", gender: .male, style: "playful"),
        
        // British
        .kokoroVoice(id: "bf_alice", name: "Alice", languageCode: "en-GB", gender: .female, style: "elegant"),
        .kokoroVoice(id: "bf_lily", name: "Lily", languageCode: "en-GB", gender: .female, style: "warm"),
        .kokoroVoice(id: "bm_daniel", name: "Daniel", languageCode: "en-GB", gender: .male, style: "refined"),
        .kokoroVoice(id: "bm_fable", name: "Fable", languageCode: "en-GB", gender: .male, style: "storyteller"),
        .kokoroVoice(id: "bm_lewis", name: "Lewis", languageCode: "en-GB", gender: .male, style: "casual"),
        
        // French
        .kokoroVoice(id: "ff_siwis", name: "Siwis", languageCode: "fr-FR", gender: .female, style: "French"),
        
        // Japanese
        .kokoroVoice(id: "jf_alpha", name: "Alpha", languageCode: "ja-JP", gender: .female),
        .kokoroVoice(id: "jf_gongitsune", name: "Gongitsune", languageCode: "ja-JP", gender: .female, style: "storyteller"),
        .kokoroVoice(id: "jf_nezumi", name: "Nezumi", languageCode: "ja-JP", gender: .female, style: "cute"),
        .kokoroVoice(id: "jf_tebukuro", name: "Tebukuro", languageCode: "ja-JP", gender: .female, style: "gentle"),
        .kokoroVoice(id: "jm_kumo", name: "Kumo", languageCode: "ja-JP", gender: .male, style: "calm"),
        
        // Korean
        .kokoroVoice(id: "kf_sarah", name: "Sarah (KR)", languageCode: "ko-KR", gender: .female),
        .kokoroVoice(id: "km_chul", name: "Chul", languageCode: "ko-KR", gender: .male),
        
        // Mandarin
        .kokoroVoice(id: "zf_xiaobei", name: "Xiaobei", languageCode: "zh-CN", gender: .female),
        .kokoroVoice(id: "zf_xiaoni", name: "Xiaoni", languageCode: "zh-CN", gender: .female, style: "warm"),
        .kokoroVoice(id: "zf_xiaoxiao", name: "Xiaoxiao", languageCode: "zh-CN", gender: .female, style: "youthful"),
        .kokoroVoice(id: "zf_xiaoyi", name: "Xiaoyi", languageCode: "zh-CN", gender: .female, style: "professional"),
        .kokoroVoice(id: "zm_yunjian", name: "Yunjian", languageCode: "zh-CN", gender: .male),
        .kokoroVoice(id: "zm_yunxi", name: "Yunxi", languageCode: "zh-CN", gender: .male, style: "calm"),
        .kokoroVoice(id: "zm_yunxia", name: "Yunxia", languageCode: "zh-CN", gender: .male, style: "energetic"),
        .kokoroVoice(id: "zm_yunyang", name: "Yunyang", languageCode: "zh-CN", gender: .male, style: "authoritative")
    ]
    
    /// All Kokoro voices
    static var allKokoroVoices: [Voice] {
        freeKokoroVoices + premiumKokoroVoices
    }
    
    /// Qwen CustomVoice presets (premium)
    static let qwenPresetVoices: [Voice] = [
        .qwenVoice(speakerId: "Chelsie", name: "Chelsie", gender: .female, style: "warm"),
        .qwenVoice(speakerId: "Ethan", name: "Ethan", gender: .male, style: "confident"),
        .qwenVoice(speakerId: "Serena", name: "Serena", gender: .female, style: "calm"),
        .qwenVoice(speakerId: "Ryan", name: "Ryan", gender: .male, style: "professional"),
        .qwenVoice(speakerId: "Vivian", name: "Vivian", gender: .female, style: "friendly"),
        .qwenVoice(speakerId: "Cherry", name: "Cherry", gender: .female, style: "youthful"),
        .qwenVoice(speakerId: "Brian", name: "Brian", gender: .male, style: "authoritative"),
        .qwenVoice(speakerId: "Echo", name: "Echo (Cloud)", gender: .neutral, style: "neutral"),
        .qwenVoice(speakerId: "Aurora", name: "Aurora", gender: .female, style: "ethereal")
    ]
    
    /// Default voice for new users
    static var defaultVoice: Voice {
        freeKokoroVoices.first!
    }
}
