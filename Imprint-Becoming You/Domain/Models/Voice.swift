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
    
    /// Two-word description of voice characteristics (e.g., ["Warm", "Expressive"])
    let adjectives: [String]
    
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
        previewAudioURL: URL? = nil,
        adjectives: [String] = []
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
        self.adjectives = adjectives
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
        style: String? = nil,
        adjectives: [String] = []
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
            style: style,
            adjectives: adjectives
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
    
    /// All English Kokoro voices available for selection.
    ///
    /// These voices are verified to exist in the iOS_TTS VoiceStyle enum.
    /// Organized by accent and gender:
    /// - American Female: 11 voices
    /// - American Male: 8 voices
    /// - British Female: 3 voices
    /// - British Male: 4 voices
    /// Total: 26 voices
    static let allEnglishKokoroVoices: [Voice] = [
        // American Female (11)
        .kokoroVoice(id: "af_heart", name: "Heart", isPremiumOnly: false, gender: .female, style: "warm", adjectives: ["Warm", "Expressive"]),
        .kokoroVoice(id: "af_bella", name: "Bella", isPremiumOnly: false, gender: .female, style: "friendly", adjectives: ["Soft", "Gentle"]),
        .kokoroVoice(id: "af_alloy", name: "Alloy", isPremiumOnly: false, gender: .female, style: "neutral", adjectives: ["Neutral", "Balanced"]),
        .kokoroVoice(id: "af_aoede", name: "Aoede", isPremiumOnly: false, gender: .female, style: "melodic", adjectives: ["Melodic", "Flowing"]),
        .kokoroVoice(id: "af_jessica", name: "Jessica", isPremiumOnly: false, gender: .female, style: "casual", adjectives: ["Casual", "Relatable"]),
        .kokoroVoice(id: "af_kore", name: "Kore", isPremiumOnly: false, gender: .female, style: "youthful", adjectives: ["Youthful", "Bright"]),
        .kokoroVoice(id: "af_nicole", name: "Nicole", isPremiumOnly: false, gender: .female, style: "professional", adjectives: ["Clear", "Professional"]),
        .kokoroVoice(id: "af_nova", name: "Nova", isPremiumOnly: false, gender: .female, style: "energetic", adjectives: ["Energetic", "Vibrant"]),
        .kokoroVoice(id: "af_river", name: "River", isPremiumOnly: false, gender: .female, style: "calm", adjectives: ["Calm", "Soothing"]),
        .kokoroVoice(id: "af_sarah", name: "Sarah", isPremiumOnly: false, gender: .female, style: "friendly", adjectives: ["Friendly", "Approachable"]),
        .kokoroVoice(id: "af_sky", name: "Sky", isPremiumOnly: false, gender: .female, style: "airy", adjectives: ["Airy", "Light"]),
        
        // American Male (8)
        .kokoroVoice(id: "am_adam", name: "Adam", isPremiumOnly: false, gender: .male, style: "confident", adjectives: ["Deep", "Confident"]),
        .kokoroVoice(id: "am_michael", name: "Michael", isPremiumOnly: false, gender: .male, style: "professional", adjectives: ["Steady", "Professional"]),
        .kokoroVoice(id: "am_echo", name: "Echo", isPremiumOnly: false, gender: .male, style: "resonant", adjectives: ["Resonant", "Rich"]),
        .kokoroVoice(id: "am_eric", name: "Eric", isPremiumOnly: false, gender: .male, style: "authoritative", adjectives: ["Strong", "Authoritative"]),
        .kokoroVoice(id: "am_fenrir", name: "Fenrir", isPremiumOnly: false, gender: .male, style: "deep", adjectives: ["Deep", "Powerful"]),
        .kokoroVoice(id: "am_liam", name: "Liam", isPremiumOnly: false, gender: .male, style: "friendly", adjectives: ["Warm", "Friendly"]),
        .kokoroVoice(id: "am_onyx", name: "Onyx", isPremiumOnly: false, gender: .male, style: "smooth", adjectives: ["Smooth", "Refined"]),
        .kokoroVoice(id: "am_puck", name: "Puck", isPremiumOnly: false, gender: .male, style: "playful", adjectives: ["Playful", "Lively"]),
        
        // British Female (3)
        .kokoroVoice(id: "bf_emma", name: "Emma", languageCode: "en-GB", isPremiumOnly: false, gender: .female, style: "warm", adjectives: ["Warm", "Articulate"]),
        .kokoroVoice(id: "bf_alice", name: "Alice", languageCode: "en-GB", isPremiumOnly: false, gender: .female, style: "elegant", adjectives: ["Refined", "Elegant"]),
        .kokoroVoice(id: "bf_lily", name: "Lily", languageCode: "en-GB", isPremiumOnly: false, gender: .female, style: "gentle", adjectives: ["Gentle", "Soft"]),
        
        // British Male (4)
        .kokoroVoice(id: "bm_george", name: "George", languageCode: "en-GB", isPremiumOnly: false, gender: .male, style: "classic", adjectives: ["Classic", "Distinguished"]),
        .kokoroVoice(id: "bm_daniel", name: "Daniel", languageCode: "en-GB", isPremiumOnly: false, gender: .male, style: "refined", adjectives: ["Warm", "Authoritative"]),
        .kokoroVoice(id: "bm_fable", name: "Fable", languageCode: "en-GB", isPremiumOnly: false, gender: .male, style: "storyteller", adjectives: ["Narrative", "Engaging"]),
        .kokoroVoice(id: "bm_lewis", name: "Lewis", languageCode: "en-GB", isPremiumOnly: false, gender: .male, style: "casual", adjectives: ["Relaxed", "Natural"])
    ]
    
    /// Free Kokoro voices (6 curated) - for backwards compatibility
    static let freeKokoroVoices: [Voice] = [
        .kokoroVoice(id: "af_heart", name: "Heart", isPremiumOnly: false, gender: .female, style: "warm"),
        .kokoroVoice(id: "af_bella", name: "Bella", isPremiumOnly: false, gender: .female, style: "friendly"),
        .kokoroVoice(id: "am_adam", name: "Adam", isPremiumOnly: false, gender: .male, style: "confident"),
        .kokoroVoice(id: "am_michael", name: "Michael", isPremiumOnly: false, gender: .male, style: "professional"),
        .kokoroVoice(id: "bf_emma", name: "Emma", languageCode: "en-GB", isPremiumOnly: false, gender: .female, style: "British"),
        .kokoroVoice(id: "bm_george", name: "George", languageCode: "en-GB", isPremiumOnly: false, gender: .male, style: "British")
    ]
    
    /// Premium Kokoro voices (non-English languages)
    static let premiumKokoroVoices: [Voice] = [
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
        allEnglishKokoroVoices + premiumKokoroVoices
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
        allEnglishKokoroVoices.first!
    }
    
    /// All English voice IDs for preview cache (raw kokoroVoiceId format).
    ///
    /// Order determines synthesis priority:
    /// 1. Default voice first
    /// 2. American Female
    /// 3. American Male
    /// 4. British Female
    /// 5. British Male
    static var allEnglishVoiceIds: [String] {
        allEnglishKokoroVoices.compactMap { $0.kokoroVoiceId }
    }
}
