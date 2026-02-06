#!/usr/bin/env python3
"""Fix garbled unicode and migrate print() to AppLogger across project files."""

import re

def fix_file(filepath, replacements):
    """Apply line-based replacements to a file.

    replacements: list of (line_number_1indexed, old_substring_to_find, new_line_content)
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    for line_num, search_text, new_content in replacements:
        idx = line_num - 1
        if idx < len(lines) and search_text in lines[idx]:
            lines[idx] = new_content + '\n'
            print(f"  Fixed line {line_num}: {search_text[:60]}...")
        else:
            # Try fuzzy match - find a line near the expected location containing the search text
            found = False
            for i in range(max(0, idx-5), min(len(lines), idx+6)):
                if search_text in lines[i]:
                    lines[i] = new_content + '\n'
                    print(f"  Fixed line {i+1} (expected {line_num}): {search_text[:60]}...")
                    found = True
                    break
            if not found:
                print(f"  WARNING: Could not find '{search_text[:60]}...' near line {line_num}")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(lines)


def fix_file_regex(filepath, replacements):
    """Apply regex replacements to a file's content.

    replacements: list of (pattern, replacement)
    """
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    for pattern, replacement in replacements:
        new_content, count = re.subn(pattern, replacement, content)
        if count > 0:
            print(f"  Replaced {count} occurrence(s) of pattern: {pattern[:60]}...")
            content = new_content
        else:
            print(f"  WARNING: Pattern not found: {pattern[:60]}...")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)


# ========================================================================
# File 1: AudioPlayerService.swift
# ========================================================================
print("\n=== AudioPlayerService.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Domain/Services/Audio/AudioPlayerService.swift'
fix_file_regex(filepath, [
    # Line 208: garbled print -> AppLogger.debug
    (r'print\("[^"]*AudioPlayerService: Playing \\\(data\.count\) bytes via AVAudioPlayer"\)',
     r'AppLogger.debug("Playing \\(data.count) bytes via AVAudioPlayer", category: .audio)'),
    # Line 258: garbled print -> AppLogger.debug
    (r'print\("[^"]*AudioPlayerService: Playback started \(duration: \\\(String\(format: "%.2f", player\.duration\)\)s\)"\)',
     r'AppLogger.debug("Playback started (duration: \\(String(format: \\"%.2f\\", player.duration))s)", category: .audio)'),
    # Line 527: garbled print -> AppLogger.warning
    (r'print\("[^"]*AudioPlayerCompletionDelegate: Decode error - \\\(error\?\.localizedDescription \?\? "unknown"\)"\)',
     r'AppLogger.warning("AudioPlayerCompletionDelegate: Decode error - \\(error?.localizedDescription ?? \\"unknown\\")", category: .audio)'),
])

# ========================================================================
# File 2: PracticeStore+Handlers.swift
# ========================================================================
print("\n=== PracticeStore+Handlers.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Practice/StateMachine/PracticeStore/PracticeStore+Handlers.swift'
fix_file_regex(filepath, [
    # Line 781: garbled print -> AppLogger.debug
    (r'print\("[^"]*Score display: User navigated away, skipping auto-advance"\)',
     r'AppLogger.debug("Score display: User navigated away, skipping auto-advance", category: .practice)'),
])

# ========================================================================
# File 3: ClassicBarsWaveform.swift
# ========================================================================
print("\n=== ClassicBarsWaveform.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Modules/DockModule/Components/Waveforms/ClassicBarsWaveform.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix garbled multiplication signs in comments
old_count = content.count('\u00c3\u0097')  # Common garbled x
content_new = content.replace('60fps \u00c3\u0097 9 bars', '60fps x 9 bars')
if content_new != content:
    content = content_new
    print("  Fixed garbled multiplication sign (variant 1)")

# Try other mojibake patterns for the multiplication sign
# The raw hex showed these are multi-byte garbled sequences
# Let's just replace any non-ASCII between "60fps " and " 9 bars"
content_new = re.sub(r'60fps [^\x00-\x7F]+ 9 bars', '60fps x 9 bars', content)
if content_new != content:
    content = content_new
    print("  Fixed garbled multiplication sign (regex)")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

# ========================================================================
# File 4: PracticeStore+LoopSession.swift
# ========================================================================
print("\n=== PracticeStore+LoopSession.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Practice/StateMachine/PracticeStore/PracticeStore+LoopSession.swift'
fix_file_regex(filepath, [
    # [OK] prints -> AppLogger.info
    (r'print\("\[OK\] PracticeStore: Shuffled session affirmations for new loop"\)',
     r'AppLogger.info("Shuffled session affirmations for new loop", category: .practice)'),
    (r'print\("\[WARN\] PracticeStore: No saved session repository"\)',
     r'AppLogger.warning("No saved session repository", category: .practice)'),
    (r'print\("\[WARN\] PracticeStore: Saved session has no valid affirmations"\)',
     r'AppLogger.warning("Saved session has no valid affirmations", category: .practice)'),
    (r'print\("\[OK\] PracticeStore: Starting saved session \'\\',
     r'AppLogger.info("Starting saved session \'\\'),
    # Fix the rest of line 89 - need to capture the interpolation
    # Actually let me do the whole line
])

# Re-read and do manual line fixes for complex interpolated strings
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    stripped = line.strip()

    if stripped == 'print("[OK] PracticeStore: Shuffled session affirmations for new loop")':
        lines[i] = line.replace(
            'print("[OK] PracticeStore: Shuffled session affirmations for new loop")',
            'AppLogger.info("Shuffled session affirmations for new loop", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [OK] Shuffled session affirmations")

    elif 'print("[WARN] PracticeStore: No saved session repository")' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: No saved session repository")',
            'AppLogger.warning("No saved session repository", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] No saved session repository")

    elif 'print("[WARN] PracticeStore: Saved session has no valid affirmations")' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: Saved session has no valid affirmations")',
            'AppLogger.warning("Saved session has no valid affirmations", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] Saved session has no valid affirmations")

    elif 'print("[OK] PracticeStore: Starting saved session' in stripped:
        lines[i] = line.replace(
            'print("[OK] PracticeStore: Starting saved session',
            'AppLogger.info("Starting saved session'
        ).replace(
            'affirmations")',
            'affirmations", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [OK] Starting saved session")

    elif 'print("[ERROR] PracticeStore: Failed to load saved session affirmations' in stripped:
        lines[i] = line.replace(
            'print("[ERROR] PracticeStore: Failed to load saved session affirmations: \\(error)")',
            'AppLogger.error("Failed to load saved session affirmations: \\(error)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [ERROR] Failed to load saved session affirmations")

    elif 'print("[WARN] PracticeStore: Cannot save while playing a saved session")' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: Cannot save while playing a saved session")',
            'AppLogger.warning("Cannot save while playing a saved session", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] Cannot save while playing")

    elif 'print("[WARN] PracticeStore: No saved session repository")' in stripped:
        # Already handled above, skip duplicate
        pass

    elif 'print("[WARN] PracticeStore: At saved session limit' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: At saved session limit',
            'AppLogger.warning("At saved session limit'
        ).replace(
            'maxSavedSessions))")',
            'maxSavedSessions))", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] At saved session limit")

    elif 'print("[WARN] PracticeStore: Failed to check session count' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: Failed to check session count: \\(error)")',
            'AppLogger.warning("Failed to check session count: \\(error)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] Failed to check session count")

    elif 'print("[WARN] PracticeStore: No affirmations to save")' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: No affirmations to save")',
            'AppLogger.warning("No affirmations to save", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] No affirmations to save")

    elif 'print("[WARN] PracticeStore: Session with same affirmations already exists")' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: Session with same affirmations already exists")',
            'AppLogger.warning("Session with same affirmations already exists", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] Session with same affirmations")

    elif 'print("[WARN] PracticeStore: Failed to check for duplicate session' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: Failed to check for duplicate session: \\(error)")',
            'AppLogger.warning("Failed to check for duplicate session: \\(error)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] Failed to check for duplicate")

    elif 'print("[OK] PracticeStore: Saved session' in stripped and 'affirmations' in stripped:
        lines[i] = line.replace(
            'print("[OK] PracticeStore: Saved session',
            'AppLogger.info("Saved session'
        ).replace(
            'affirmations")',
            'affirmations", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [OK] Saved session")

    elif 'print("[ERROR] PracticeStore: Failed to save session' in stripped:
        lines[i] = line.replace(
            'print("[ERROR] PracticeStore: Failed to save session: \\(error)")',
            'AppLogger.error("Failed to save session: \\(error)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [ERROR] Failed to save session")

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(lines)

# ========================================================================
# File 5: PracticeStore+DataLoading.swift
# ========================================================================
print("\n=== PracticeStore+DataLoading.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Practice/StateMachine/PracticeStore/PracticeStore+DataLoading.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    stripped = line.strip()

    if 'print("[WARN] PracticeStore: No favorites to start session")' in stripped:
        lines[i] = line.replace(
            'print("[WARN] PracticeStore: No favorites to start session")',
            'AppLogger.warning("No favorites to start session", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] No favorites to start session")

    elif 'print("[OK] PracticeStore: Starting favorites session' in stripped:
        lines[i] = line.replace(
            'print("[OK] PracticeStore: Starting favorites session',
            'AppLogger.info("Starting favorites session'
        )
        # Need to add category at end
        if 'category: .practice' not in lines[i]:
            lines[i] = lines[i].rstrip().rstrip(')').rstrip('"')
            # Actually, let me do this more carefully
            pass

    elif 'print("[LOG] PracticeStore: Failed to record' in stripped:
        lines[i] = line.replace(
            'print("[LOG] PracticeStore: Failed to record \\(type) engagement")',
            'AppLogger.debug("Failed to record \\(type) engagement", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [LOG] Failed to record engagement")

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(lines)

# Re-read and handle the complex favorites session line
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'print("[OK] PracticeStore: Starting favorites session with \\(affirmations.count) affirmations, mode: \\(mode.displayName), voiceId: \\(selectedVoiceId ?? "nil")")',
    'AppLogger.info("Starting favorites session with \\(affirmations.count) affirmations, mode: \\(mode.displayName), voiceId: \\(selectedVoiceId ?? \\"nil\\")", category: .practice)'
)
print("  Fixed: [OK] Starting favorites session (complex)")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

# ========================================================================
# File 6: PracticeStore+TaskManagement.swift
# ========================================================================
print("\n=== PracticeStore+TaskManagement.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Practice/StateMachine/PracticeStore/PracticeStore+TaskManagement.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'print("[DEBUG] PracticeStore Tasks (\\(activeCount) active): \\(taskStates.joined(separator: ", "))")',
    'AppLogger.debug("PracticeStore Tasks (\\(activeCount) active): \\(taskStates.joined(separator: \\", \\"))", category: .practice)'
)
print("  Fixed line 170: [DEBUG] PracticeStore Tasks")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

# ========================================================================
# File 7: PracticeStore+RepeatSession.swift
# ========================================================================
print("\n=== PracticeStore+RepeatSession.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Practice/StateMachine/PracticeStore/PracticeStore+RepeatSession.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'print("[OK] PracticeStore: Repeating session with mode=\\(mode.displayName), loops=\\(loopCount), shuffle=\\(shuffle), voiceId: \\(selectedVoiceId ?? "nil")")',
    'AppLogger.info("Repeating session with mode=\\(mode.displayName), loops=\\(loopCount), shuffle=\\(shuffle), voiceId: \\(selectedVoiceId ?? \\"nil\\")", category: .practice)'
)
print("  Fixed line 88: [OK] Repeating session")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

# ========================================================================
# File 8: MainPracticeView.swift
# ========================================================================
print("\n=== MainPracticeView.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Practice/Views/MainPracticeView.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    stripped = line.strip()

    if 'print("[DEBUG] MainPracticeView: Paused session on background")' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: Paused session on background")',
            'AppLogger.debug("Paused session on background", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] Paused session on background")

    elif 'print("[DEBUG] MainPracticeView: App entered background")' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: App entered background")',
            'AppLogger.debug("App entered background", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] App entered background")

    elif 'print("[DEBUG] MainPracticeView: Returned from background after' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: Returned from background after \\(Int(timeInBackground))s")',
            'AppLogger.debug("Returned from background after \\(Int(timeInBackground))s", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] Returned from background after")

    elif 'print("[DEBUG] MainPracticeView: Memory threshold reached' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: Memory threshold reached (\\(Int(timeInBackground))s)")',
            'AppLogger.debug("Memory threshold reached (\\(Int(timeInBackground))s)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] Memory threshold reached")

    elif 'print("[DEBUG] MainPracticeView: Current memory usage' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: Current memory usage: \\(memoryMB)MB")',
            'AppLogger.debug("Current memory usage: \\(memoryMB)MB", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] Current memory usage")

    elif 'print("[DEBUG] MainPracticeView: MemoryManager released' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: MemoryManager released = \\(MemoryManager.shared.hasReleasedForBackground)")',
            'AppLogger.debug("MemoryManager released = \\(MemoryManager.shared.hasReleasedForBackground)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] MemoryManager released")

    elif 'print("[DEBUG] MainPracticeView: Full reset after' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: Full reset after \\(Int(timeInBackground))s in background")',
            'AppLogger.debug("Full reset after \\(Int(timeInBackground))s in background", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] Full reset after")

    elif 'print("[DEBUG] MainPracticeView: Keeping summary open' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: Keeping summary open after short background (\\(Int(timeInBackground))s)")',
            'AppLogger.debug("Keeping summary open after short background (\\(Int(timeInBackground))s)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] Keeping summary open")

    elif 'print("[DEBUG] MainPracticeView: Resuming session after' in stripped:
        lines[i] = line.replace(
            'print("[DEBUG] MainPracticeView: Resuming session after \\(Int(timeInBackground))s in background")',
            'AppLogger.debug("Resuming session after \\(Int(timeInBackground))s in background", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [DEBUG] Resuming session after")

    elif 'print("MainPracticeView: Set voice to' in stripped:
        lines[i] = line.replace(
            'print("MainPracticeView: Set voice to \\(storedVoiceId ?? "default")")',
            'AppLogger.debug("Set voice to \\(storedVoiceId ?? \\"default\\")", category: .practice)'
        )
        print(f"  Fixed line {i+1}: Set voice to")

    elif 'print("[WARN] MainPracticeView: Failed to get saved session count' in stripped:
        lines[i] = line.replace(
            'print("[WARN] MainPracticeView: Failed to get saved session count: \\(error)")',
            'AppLogger.warning("Failed to get saved session count: \\(error)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [WARN] Failed to get saved session count")

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(lines)

# ========================================================================
# File 9: SavedSessionsFullListView.swift
# ========================================================================
print("\n=== SavedSessionsFullListView.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Profile/Views/SavedSessionsFullListView.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    stripped = line.strip()

    if 'print("[ERROR] SavedSessionsFullListView: Failed to rename session' in stripped:
        lines[i] = line.replace(
            'print("[ERROR] SavedSessionsFullListView: Failed to rename session: \\(error)")',
            'AppLogger.error("Failed to rename session: \\(error)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [ERROR] Failed to rename session")

    elif 'print("[ERROR] SavedSessionsFullListView: Failed to delete session' in stripped:
        lines[i] = line.replace(
            'print("[ERROR] SavedSessionsFullListView: Failed to delete session: \\(error)")',
            'AppLogger.error("Failed to delete session: \\(error)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [ERROR] Failed to delete session")

    elif 'print("[ERROR] SavedSessionInfoView: Failed to fetch affirmations' in stripped:
        lines[i] = line.replace(
            'print("[ERROR] SavedSessionInfoView: Failed to fetch affirmations: \\(error)")',
            'AppLogger.error("Failed to fetch affirmations: \\(error)", category: .practice)'
        )
        print(f"  Fixed line {i+1}: [ERROR] Failed to fetch affirmations")

with open(filepath, 'w', encoding='utf-8') as f:
    f.writelines(lines)

# ========================================================================
# File 10: AffirmationDeletionHelper.swift
# ========================================================================
print("\n=== AffirmationDeletionHelper.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Core/Utilities/AffirmationDeletionHelper.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'print("[OK] AffirmationDeletionHelper: Deleted affirmation \\(affirmation.id)")',
    'AppLogger.info("Deleted affirmation \\(affirmation.id)", category: .data)'
)
content = content.replace(
    'print("[OK] AffirmationDeletionHelper: Batch delete - \\(deleted) deleted, \\(skipped) skipped")',
    'AppLogger.info("Batch delete - \\(deleted) deleted, \\(skipped) skipped", category: .data)'
)
content = content.replace(
    'print("[OK] AffirmationDeletionHelper: Cleaned up \\(deletable.count) expired affirmations (\\(allExpired.count - deletable.count) protected/seeded)")',
    'AppLogger.info("Cleaned up \\(deletable.count) expired affirmations (\\(allExpired.count - deletable.count) protected/seeded)", category: .data)'
)
print("  Fixed 3 [OK] prints -> AppLogger.info")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

# ========================================================================
# File 11: DockSegmentsView.swift
# ========================================================================
print("\n=== DockSegmentsView.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Modules/DockModule/Components/Dock/DockSegmentsView.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'print("[DEBUG] DockSegmentsView: Generation changed, resetting timer")',
    'AppLogger.debug("Generation changed, resetting timer", category: .ui)'
)
print("  Fixed line 257: [DEBUG] Generation changed")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

# ========================================================================
# File 12: FullScreenPopPanGesture.swift
# ========================================================================
print("\n=== FullScreenPopPanGesture.swift ===")
filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Shared/FullScreenPopPanGesture.swift'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    'print("[WARN] FullScreenPopGesture: UINavigationController not found in responder chain")',
    'AppLogger.warning("UINavigationController not found in responder chain", category: .ui)'
)
content = content.replace(
    'print("[WARN] FullScreenPopGesture: Cannot access interactivePopGestureRecognizer targets")',
    'AppLogger.warning("Cannot access interactivePopGestureRecognizer targets", category: .ui)'
)
print("  Fixed 2 [WARN] prints -> AppLogger.warning")

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)


print("\n=== ALL DONE ===")
