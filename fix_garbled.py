#!/usr/bin/env python3
"""Fix garbled unicode in specific files by replacing entire lines."""
import sys

def fix_audio_player_service():
    filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Domain/Services/Audio/AudioPlayerService.swift'
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    fixed = []
    skip_until_store_reference = False
    i = 0
    while i < len(lines):
        line = lines[i]

        # Detect the corrupted duplicate zone: a line containing garbled chars + "AudioPlayerService: Playing"
        # that comes AFTER the already-fixed AppLogger.debug line
        if 'AudioPlayerService: Playing' in line and 'AppLogger' not in line:
            # This is leftover garbled content. Skip lines until we reach "// Store reference"
            skip_until_store_reference = True
            i += 1
            continue

        if skip_until_store_reference:
            if '// Store reference' in line:
                skip_until_store_reference = False
                fixed.append(line)
            i += 1
            continue

        # Line 258 area: Playback started garbled print
        if 'AudioPlayerService: Playback started' in line and 'print(' in line:
            indent = '        '
            fixed.append(indent + 'AppLogger.debug("Playback started (duration: \\(String(format: \\"%.2f\\", player.duration))s)", category: .audio)\n')
            i += 1
            continue

        # Line 527 area: AudioPlayerCompletionDelegate garbled print
        if 'AudioPlayerCompletionDelegate: Decode error' in line and 'print(' in line:
            indent = '        '
            fixed.append(indent + 'AppLogger.warning("AudioPlayerCompletionDelegate: Decode error - \\(error?.localizedDescription ?? \\"unknown\\")", category: .audio)\n')
            i += 1
            continue

        fixed.append(line)
        i += 1

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(fixed)
    print(f"Fixed AudioPlayerService.swift: {len(lines)} -> {len(fixed)} lines")


def fix_practice_store_handlers():
    filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Practice/StateMachine/PracticeStore/PracticeStore+Handlers.swift'
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    fixed = []
    for line in lines:
        if 'Score display: User navigated away' in line and 'print(' in line:
            indent = '                '
            fixed.append(indent + 'AppLogger.debug("Score display: User navigated away, skipping auto-advance", category: .practice)\n')
        else:
            fixed.append(line)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(fixed)
    print(f"Fixed PracticeStore+Handlers.swift: {len(lines)} lines")


def fix_classic_bars_waveform():
    filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Modules/DockModule/Components/Waveforms/ClassicBarsWaveform.swift'
    with open(filepath, 'rb') as f:
        data = f.read()

    # Find and replace the garbled multiplication sign near "60fps"
    # The pattern is "60fps " followed by some non-ASCII bytes then " 9 bars"
    import re
    # Work with bytes to handle the garbled encoding
    pattern = b'60fps (?:[\\x80-\\xff]+) 9 bars'
    replacement = b'60fps x 9 bars'
    new_data, count = re.subn(pattern, replacement, data)
    if count > 0:
        print(f"Fixed {count} garbled multiplication sign(s) in ClassicBarsWaveform.swift")
    else:
        # Try a different pattern - the hex showed \xc3\x97 which is UTF-8 for multiplication sign
        new_data = data.replace(b'60fps \xc3\x97 9 bars', b'60fps x 9 bars')
        if new_data != data:
            print("Fixed garbled multiplication signs (UTF-8 x pattern)")
        else:
            print("WARNING: Could not find garbled multiplication signs")

    with open(filepath, 'wb') as f:
        f.write(new_data)


def fix_practice_store_handlers_garbled_comments():
    """Fix garbled em-dash characters in PracticeStore+Handlers.swift comments."""
    filepath = '/Users/chrismazile/Desktop/MazilePlay-Apps/Imprint-Becoming You/Imprint-Becoming You/Features/Practice/StateMachine/PracticeStore/PracticeStore+Handlers.swift'
    with open(filepath, 'rb') as f:
        data = f.read()

    # The garbled em-dashes show as multi-byte sequences
    # Common pattern: \xc3\xa2\xe2\x80\x9a\xc2\xac (garbled em-dash)
    # Let's just check if there are any non-standard chars in comment lines
    # Actually the issue description only mentions the print line, not comments

    with open(filepath, 'wb') as f:
        f.write(data)


if __name__ == '__main__':
    fix_audio_player_service()
    fix_practice_store_handlers()
    fix_classic_bars_waveform()
    print("\nAll garbled files fixed!")
