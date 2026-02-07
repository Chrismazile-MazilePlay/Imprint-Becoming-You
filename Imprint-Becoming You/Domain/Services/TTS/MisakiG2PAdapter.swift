//
//  MisakiG2PAdapter.swift
//  Imprint-Becoming You
//
//  Created by Christopher Mazile on 2/7/26.
//

import Foundation
import iOS_TTS
import MisakiSwift
import MLXUtilsLibrary

// MARK: - MisakiSwift G2P Adapter

/// Bridges MisakiSwift's `EnglishG2P` to the `iOS_TTS.G2P` protocol.
///
/// Implements the Dependency Inversion principle: neither library knows about
/// the other. The app owns composition by importing both and bridging their types.
///
/// ## Thread Safety
/// `NLTagger` (used internally by `EnglishG2P`) is NOT thread-safe.
/// All G2P operations are serialized through a dedicated `DispatchQueue`
/// to guarantee `NLTagger` is always accessed from a consistent thread.
/// This prevents the `EXC_BAD_ACCESS` crash that occurs when Swift's
/// cooperative thread pool migrates execution across async boundaries.
///
/// ## Usage
/// ```swift
/// let adapter = MisakiG2PAdapter(british: false)
/// let pipeline = try TTSPipeline(..., g2p: adapter)
/// ```
final class MisakiG2PAdapter: iOS_TTS.G2P {

    // MARK: - Properties

    /// Serial queue ensuring all `NLTagger` operations execute on a single,
    /// consistent thread. Prevents data races when `TTSPipeline.generate()`
    /// (async) calls `g2p.convert()` from cooperative thread pool threads.
    private let g2pQueue: DispatchQueue
    private let engine: EnglishG2P

    // MARK: - Initialization

    /// Creates a new adapter for the specified English dialect.
    ///
    /// The `EnglishG2P` engine (and its internal `NLTagger`) is created on the
    /// serial queue to ensure thread affinity from birth through all usage.
    ///
    /// - Parameter british: `true` for British English (en-GB), `false` for American English (en-US).
    init(british: Bool) {
        let queue = DispatchQueue(label: "com.imprint.misaki-g2p")
        self.g2pQueue = queue
        self.engine = queue.sync {
            EnglishG2P(british: british)
        }
    }

    // MARK: - G2P Protocol

    func convert(_ text: String) throws -> iOS_TTS.G2PResult {
        let (phonemeString, misakiTokens) = g2pQueue.sync {
            engine.phonemize(text: text)
        }
        let tokens = misakiTokens.map { convertToken($0) }
        return iOS_TTS.G2PResult(phonemeString: phonemeString, tokens: tokens)
    }

    // MARK: - Private

    /// Converts a MisakiSwift `MToken` to an iOS_TTS `MToken`.
    ///
    /// Bridges differences:
    /// - `MLXUtilsLibrary.MToken.tag` is `NLTag?` → `iOS_TTS.MToken.tag` is `String`
    /// - `MLXUtilsLibrary.Underscore` uses snake_case → `iOS_TTS.MToken.Underscore` uses camelCase
    private func convertToken(_ token: MLXUtilsLibrary.MToken) -> iOS_TTS.MToken {
        iOS_TTS.MToken(
            text: token.text,
            tag: token.tag?.rawValue ?? "",
            whitespace: token.whitespace,
            phonemes: token.phonemes,
            startTs: token.start_ts,
            endTs: token.end_ts,
            underscore: iOS_TTS.MToken.Underscore(
                isHead: token.`_`.is_head,
                alias: token.`_`.alias,
                stress: token.`_`.stress,
                currency: token.`_`.currency,
                numFlags: token.`_`.num_flags,
                prespace: token.`_`.prespace,
                rating: token.`_`.rating
            )
        )
    }
}
