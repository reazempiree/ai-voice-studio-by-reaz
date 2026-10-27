#!/usr/bin/env bash
# The published environment snapshot retains /workspace/tools and android-sdk.
# This refreshes dependencies without downloading models or touching user audio.
set -euo pipefail
cd /workspace/ai-voice-studio-by-reaz
export PUB_CACHE=/workspace/.pub-cache
export XDG_CONFIG_HOME=/workspace/.config
export ANDROID_HOME=/workspace/android-sdk
export ANDROID_USER_HOME=/workspace/.android
export GRADLE_USER_HOME=/workspace/.gradle
export PATH="/workspace/tools/flutter/bin:$PATH"
command -v flutter >/dev/null
command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null
test -x /workspace/tools/jdk-17.0.21+9/bin/javac
flutter config --jdk-dir=/workspace/tools/jdk-17.0.21+9
flutter pub get --enforce-lockfile
python3 -m venv /workspace/voice-backend-venv
/workspace/voice-backend-venv/bin/pip install -r backend/requirements.lock.txt
