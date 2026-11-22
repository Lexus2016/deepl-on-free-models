#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

MODEL_SOURCE="${HYMT_MODEL_SOURCE:-maternion/hy-mt2:7b}"
MODEL_ALIAS="${HYMT_MODEL_ALIAS:-hy-mt2:7b}"

echo "==> Перевірка Ollama"
if ! command -v ollama >/dev/null 2>&1; then
    echo "Ollama не встановлено. Встановіть: brew install ollama" >&2
    exit 1
fi

if ! curl -sf --max-time 3 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "Сервер Ollama не відповідає. Запустіть 'ollama serve' і повторіть." >&2
    exit 1
fi

echo "==> Модель $MODEL_ALIAS"
if ollama list | awk 'NR>1 {print $1}' | grep -qx "$MODEL_ALIAS"; then
    echo "Модель уже встановлена."
else
    ollama pull "$MODEL_SOURCE"
    ollama cp "$MODEL_SOURCE" "$MODEL_ALIAS"
fi

echo "==> Тестовий переклад"
python3 - "$MODEL_ALIAS" <<'PY'
import json
import sys
import urllib.request

model = sys.argv[1]
prompt = (
    "Translate the following text into Ukrainian. Note that you should only output "
    "the translated result without any additional explanation:\n\n"
    "Energetic acoustic pop, a vibrant male baritone, guitar, and light percussion, 100 BPM"
)
options = {
    "temperature": 0.7,
    "top_p": 0.6,
    "top_k": 20,
    "repeat_penalty": 1.05,
    "stop": ["hy_end", "<｜hy_place▁holder▁no▁8｜>", "<｜hy_place▁holder▁no▁2｜>"],
}
for attempt in range(3):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "options": options,
    }).encode()
    request = urllib.request.Request(
        "http://127.0.0.1:11434/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        payload = json.load(response)
    text = payload.get("message", {}).get("content", "").strip()
    if text:
        print(text)
        break
else:
    print("Модель кілька разів повернула порожній результат — спробуйте переклад у застосунку.")
PY

echo "==> Збірка застосунку"
./build.sh

echo
echo "Готово. Запуск: open build/DeepL-oFM.app"
