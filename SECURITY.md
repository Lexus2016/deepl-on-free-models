# Security

## Keys and secrets

- API keys are stored in the **macOS Keychain**, one item per provider
  (`service = ua.admin.hymt`, `account = provider:<id>`). New items use the
  `kSecAttrAccessibleAfterFirstUnlock` protection class.
- Keys are never written to `UserDefaults`, translation history, logs or files
  in the repository.
- The repository contains no `.env` files, tokens, private keys or models.
  `.gitignore` excludes `.env`, `*.key`, `*.pem`, `*.gguf`, `build/`, `.build/`
  and logs.
- If a key ever reaches a commit or a public repository, revoke it in the
  provider's panel immediately. Treat the git history as compromised: the key
  must be considered public even if the commit is removed later.

## Privacy

- Local providers (Ollama, LM Studio, oMLX, llama.cpp) do not send the text over
  the network.
- Cloud providers (Ollama Cloud, OpenRouter, Groq, Cerebras) receive the text
  being translated under their own terms and data policies.
- The app has no telemetry, analytics or background connection to its authors'
  servers.
- The **Accessibility** permission is used only to send `⌘C` to the active app
  before translating selected text. The app does not read keyboard events or
  collect the contents of other windows.
- Translation history is stored locally in
  `~/Library/Application Support/DeepL-oFM/history.json` and can be cleared from
  the History tab. Disable **Keep translation history** to stop writing it.

## Reporting a vulnerability

Do not open a public issue with exploit details. Use GitHub
**Security → Report a vulnerability** (private advisory) in this repository.

Please include:

- version/commit;
- macOS version and how the app was launched (local build or `/Applications`);
- reproduction steps;
- expected and actual behaviour;
- whether the issue affects API keys or user data.

You can expect a response within 7 days. Please do not publish details before a
fix is available.
