# VPStudio OpenClaw provider / routing policy

This file is the canonical reference for provider routing rules the VPStudio cron lanes should follow.

## LiteLLM base
- Base URL: `https://litellm.tgk30.com/v1`

## Use these standard inference endpoints
- **Chat / text:** `POST /chat/completions`
- **Images:** `POST /images/generations`
- **Video create:** `POST /videos`
- **Video create compatibility path:** `POST /videos/generations`
- **Embeddings:** `POST /embeddings`

## Do not use these for normal inference
- `/v2/model/info`
- `/v1/model/info`
- `/model/new`
- `/model/update`
- `/credentials/...`

Those are admin/debug endpoints and should not be used for normal generation work.

## Preferred models for VPStudio
- **UI reasoning / screenshot analysis:** `litellm/google-gemini-3.1-pro-preview`
- **Image generation:** `google-gemini-3.1-flash-image-preview`
- **Fast coding:** `openai-codex/gpt-5.3-codex`
- **Deep coding:** `openai-codex/gpt-5.4`
- **Cheap coordination / guardrails:** `litellm/MiniMax-M2.7`
- **Premium review:** `anthropic/claude-sonnet-4-6`
- **Manual escalation only:** `anthropic/claude-opus-4-6`

## Image generation policy
For item **#9** and any other art-backed UI work:
1. Reason and review with **Gemini Pro**.
2. Generate images through `POST /images/generations`.
3. Use model `google-gemini-3.1-flash-image-preview`.
4. Do not prefer `/chat/completions` for image generation when `/images/generations` is available.
5. If image generation does not behave as expected, record the exact failure and keep the work item in progress rather than faking success.
