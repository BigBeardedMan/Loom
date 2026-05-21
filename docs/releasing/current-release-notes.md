## Changes

- Mac dictation now starts the speech task before microphone capture and reports a clear error if the mic tap delivers no audio.
- Mac dictation no longer crashes when the microphone audio tap starts under Swift 6 strict concurrency.
- Windows Testing now uses the Mac-style shell, left navigation, workspace rows, and usage surfaces instead of the older Windows-only layout.
- The Windows LM Studio usage view no longer shows a limits control, and recently closed prompt previews now close from outside-click or Escape.
- Windows terminal clicks on the active input row now move the shell cursor toward the clicked character.
- Recently closed terminal restores now bound the imported terminal scrollback so large transcripts cannot stall the app.
- Transcript previews can reveal the saved transcript file in Finder when the full history is larger than the in-app preview.
- Usage dashboards now carry their selected Day, Week, Month, or Year range through the snapshot and show range-specific session counts.
- Notes editing now debounces SwiftData saves instead of saving on every keystroke.
- Sidebar and transcript controls now include clearer accessibility labels.
