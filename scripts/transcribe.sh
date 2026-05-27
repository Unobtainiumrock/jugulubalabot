#!/usr/bin/env bash
# Transcribe an audio file using faster-whisper.
# Usage: transcribe.sh <audio-file> [model]
set -euo pipefail
audio="${1:?audio file required}"
model="${2:-base}"
exec /root/.openclaw/venvs/whisper/bin/python3 - "$audio" "$model" <<'PY'
import sys
from faster_whisper import WhisperModel
audio, model_name = sys.argv[1], sys.argv[2]
model = WhisperModel(model_name, device="cpu", compute_type="int8")
segments, info = model.transcribe(audio, vad_filter=True)
for seg in segments:
    print(seg.text.strip())
PY
