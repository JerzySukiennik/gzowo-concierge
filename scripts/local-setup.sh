#!/bin/zsh
# Gzowo Concierge - installs the offline mode into ~/.gzowo-concierge/local: llama.cpp server for Intel macOS, the local chat model (GGUF) and the whisper model for offline dictation. Safe to re-run.
set -e
LOCAL="${LOCAL_DIR:-$HOME/.gzowo-concierge/local}"
LLAMA_TAG="${LLAMA_TAG:-b12441}"
MODEL="${1:-gemma4-e4b}"
case "$MODEL" in
  bielik-4.5b) REPO=second-state/Bielik-4.5B-v3.0-Instruct-GGUF; FILE=Bielik-4.5B-v3.0-Instruct-Q4_K_M.gguf ;;
  qwen3.5-4b) REPO=unsloth/Qwen3.5-4B-GGUF; FILE=Qwen3.5-4B-Q4_K_M.gguf ;;
  gemma4-e2b) REPO=unsloth/gemma-4-E2B-it-GGUF; FILE=gemma-4-E2B-it-Q4_K_M.gguf ;;
  gemma4-e4b) REPO=unsloth/gemma-4-E4B-it-GGUF; FILE=gemma-4-E4B-it-Q4_K_M.gguf ;;
  *) echo "unknown model: $MODEL"; exit 1 ;;
esac
mkdir -p "$LOCAL/bin" "$LOCAL/models"
if [ ! -x "$LOCAL/bin/llama-server" ] || ! "$LOCAL/bin/llama-server" --version 2>&1 | grep -q "build ${LLAMA_TAG#b}"; then
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/llama.tgz" "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_TAG/llama-$LLAMA_TAG-bin-macos-x64.tar.gz"
  tar -xzf "$TMP/llama.tgz" -C "$TMP"
  rsync -a --delete "$TMP/llama-$LLAMA_TAG/" "$LOCAL/bin/"
  rm -rf "$TMP"
  echo "llama.cpp $LLAMA_TAG installed"
fi
fetch() {
  [ -s "$LOCAL/models/$2" ] && return
  curl -fSL --retry 3 -C - -o "$LOCAL/models/$2.part" "https://huggingface.co/$1/resolve/main/$2"
  mv "$LOCAL/models/$2.part" "$LOCAL/models/$2"
  echo "downloaded $2"
}
fetch "$REPO" "$FILE"
fetch ggerganov/whisper.cpp ggml-large-v3-turbo-q5_0.bin
command -v whisper-cli >/dev/null || [ -x /usr/local/bin/whisper-cli ] || brew install whisper-cpp
echo "offline mode ready: $MODEL"
