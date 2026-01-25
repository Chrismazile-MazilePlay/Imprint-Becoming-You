//
//  KokoroVoice.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 1/24/26.
//

import Foundation
import iOS_TTS

// MARK: - Kokoro Voice

/// Enum representing available Kokoro TTS voices.
///
/// Maps to the iOS_TTS library's VoiceStyle enum while providing
/// app-specific metadata like display names and categorization.
///
/// ## Voice ID Format
/// Kokoro voice IDs use the prefix `kokoro_` followed by the case name:
/// - `kokoro_afHeart` -> American Female "Heart"
/// - `kokoro_amAdam` -> American Male "Adam"
///
/// ## Usage
/// ```swift
/// // Get voice from voiceId string
/// if let voice = KokoroVoice(voiceId: "kokoro_afHeart") {
///     let style = voice.voiceStyle
///     // Use with TTSPipeline
/// }
///
/// // Get all American female voices
/// let voices = KokoroVoice.americanFemale
/// ```
enum KokoroVoice: String, CaseIterable, Sendable {
    
    // MARK: - American Female
    
    case afAlloy = "kokoro_afAlloy"
    case afAoede = "kokoro_afAoede"
    case afBella = "kokoro_afBella"
    case afHeart = "kokoro_afHeart"
    case afJessica = "kokoro_afJessica"
    case afKore = "kokoro_afKore"
    case afNicole = "kokoro_afNicole"
    case afNova = "kokoro_afNova"
    case afRiver = "kokoro_afRiver"
    case afSarah = "kokoro_afSarah"
    case afSky = "kokoro_afSky"
    
    // MARK: - American Male
    
    case amAdam = "kokoro_amAdam"
    case amEcho = "kokoro_amEcho"
    case amEric = "kokoro_amEric"
    case amFenrir = "kokoro_amFenrir"
    case amLiam = "kokoro_amLiam"
    case amMichael = "kokoro_amMichael"
    case amOnyx = "kokoro_amOnyx"
    case amPuck = "kokoro_amPuck"
    case amSanta = "kokoro_amSanta"
    
    // MARK: - British Female
    
    case bfAlice = "kokoro_bfAlice"
    case bfEmma = "kokoro_bfEmma"
    case bfIsabella = "kokoro_bfIsabella"
    case bfLily = "kokoro_bfLily"
    
    // MARK: - British Male
    
    case bmDaniel = "kokoro_bmDaniel"
    case bmFable = "kokoro_bmFable"
    case bmGeorge = "kokoro_bmGeorge"
    case bmLewis = "kokoro_bmLewis"
    
    // MARK: - Properties
    
    /// The voice ID string (includes "kokoro_" prefix)
    var voiceId: String {
        rawValue
    }
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .afAlloy: return "Alloy"
        case .afAoede: return "Aoede"
        case .afBella: return "Bella"
        case .afHeart: return "Heart"
        case .afJessica: return "Jessica"
        case .afKore: return "Kore"
        case .afNicole: return "Nicole"
        case .afNova: return "Nova"
        case .afRiver: return "River"
        case .afSarah: return "Sarah"
        case .afSky: return "Sky"
        case .amAdam: return "Adam"
        case .amEcho: return "Echo"
        case .amEric: return "Eric"
        case .amFenrir: return "Fenrir"
        case .amLiam: return "Liam"
        case .amMichael: return "Michael"
        case .amOnyx: return "Onyx"
        case .amPuck: return "Puck"
        case .amSanta: return "Santa"
        case .bfAlice: return "Alice"
        case .bfEmma: return "Emma"
        case .bfIsabella: return "Isabella"
        case .bfLily: return "Lily"
        case .bmDaniel: return "Daniel"
        case .bmFable: return "Fable"
        case .bmGeorge: return "George"
        case .bmLewis: return "Lewis"
        }
    }
    
    /// Gender of the voice
    var isFemale: Bool {
        rawValue.contains("_af") || rawValue.contains("_bf")
    }
    
    /// Whether this is a British accent
    var isBritish: Bool {
        rawValue.contains("_bf") || rawValue.contains("_bm")
    }
    
    /// Maps to iOS_TTS VoiceStyle for the TTSPipeline
    var voiceStyle: VoiceStyle {
        switch self {
        case .afAlloy: return .afAlloy
        case .afAoede: return .afAoede
        case .afBella: return .afBella
        case .afHeart: return .afHeart
        case .afJessica: return .afJessica
        case .afKore: return .afKore
        case .afNicole: return .afNicole
        case .afNova: return .afNova
        case .afRiver: return .afRiver
        case .afSarah: return .afSarah
        case .afSky: return .afSky
        case .amAdam: return .amAdam
        case .amEcho: return .amEcho
        case .amEric: return .amEric
        case .amFenrir: return .amFenrir
        case .amLiam: return .amLiam
        case .amMichael: return .amMichael
        case .amOnyx: return .amOnyx
        case .amPuck: return .amPuck
        case .amSanta: return .amSanta
        case .bfAlice: return .bfAlice
        case .bfEmma: return .bfEmma
        case .bfIsabella: return .bfIsabella
        case .bfLily: return .bfLily
        case .bmDaniel: return .bmDaniel
        case .bmFable: return .bmFable
        case .bmGeorge: return .bmGeorge
        case .bmLewis: return .bmLewis
        }
    }
    
    // MARK: - Initialization
    
    /// Creates a KokoroVoice from a voiceId string.
    ///
    /// - Parameter voiceId: Voice ID string (e.g., "kokoro_afHeart")
    /// - Returns: The matching voice, or nil if not found
    init?(voiceId: String) {
        self.init(rawValue: voiceId)
    }
    
    // MARK: - Static Accessors
    
    /// Default voice for the app
    static let `default`: KokoroVoice = .afHeart
    
    /// All American female voices
    static let americanFemale: [KokoroVoice] = [
        .afAlloy, .afAoede, .afBella, .afHeart, .afJessica,
        .afKore, .afNicole, .afNova, .afRiver, .afSarah, .afSky
    ]
    
    /// All American male voices
    static let americanMale: [KokoroVoice] = [
        .amAdam, .amEcho, .amEric, .amFenrir, .amLiam,
        .amMichael, .amOnyx, .amPuck, .amSanta
    ]
    
    /// All British female voices
    static let britishFemale: [KokoroVoice] = [
        .bfAlice, .bfEmma, .bfIsabella, .bfLily
    ]
    
    /// All British male voices
    static let britishMale: [KokoroVoice] = [
        .bmDaniel, .bmFable, .bmGeorge, .bmLewis
    ]
    
    /// All female voices
    static let allFemale: [KokoroVoice] = americanFemale + britishFemale
    
    /// All male voices
    static let allMale: [KokoroVoice] = americanMale + britishMale
    
    // MARK: - Voice ID Helpers
    
    /// Checks if a voiceId string is a Kokoro voice
    static func isKokoroVoiceId(_ voiceId: String?) -> Bool {
        guard let voiceId = voiceId else { return false }
        return voiceId.hasPrefix("kokoro_")
    }
}
