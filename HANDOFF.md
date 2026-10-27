# HANDOFF: set up vLLM on another Jetson AGX Orin

Written 2026-10-27 for a coding agent doing the setup on a new Orin. Commands and background
are in [README.md](README.md). This file covers the order of steps, what to check, and the
traps we already hit.

## Goal

The new Orin serves `qwen3.6-35b-a3b` through the OpenAI-compatible API on port 8091, the same
way the original Orin does. The DMSHI-PALette-PoC `Realtime/` side connects to it.

**Done when** this returns a model list containing `qwen3.6-35b-a3b`:

```bash
curl --noproxy '*' localhost:8091/v1/models
```

…and the smoke test below answers "red".

## State as of the handoff

- Repo: `https://github.com/hunterzhongME/vllm-jetson-orin` (private).
- Image: `ghcr.io/hunterzhongme/vllm-orin:0.29` (private package, 16.3 GB, 9.5 GB compressed). The image ID is in
  `artifacts.lock.json`.
- The original Orin keeps the build tree in `/mnt/ros_data/vllm29` and the models in
  `/mnt/ros_data/hf`. It can be the rsync source if ghcr.io or Hugging Face can't be reached.
- **Do not rebuild the wheel or the image.** The image is finished and works as is. Rebuilding
  the wheel takes hours and is only needed to change vLLM itself.

## Steps

1. **Check the host:** run `scripts/check-host.sh` and confirm every line is `ok`. It needs an
   AGX Orin 64GB on L4T R36.4.x with the nvidia Docker runtime. If the board or JetPack doesn't
   match, stop and report: the image cannot work there, and there is no workaround.
2. **Choose the disk:** the scripts default to `/mnt/ros_data/...`. If the new Orin has no such
   path, pick a disk with about 60 GB free (the root eMMC is too small) and export `HF_DIR` and
   `CACHE_DIR` for every script.
3. **Log in to ghcr.io:** the human has to do this step (see "Traps").
4. **Pull the image and tag it locally:**
   ```bash
   docker pull ghcr.io/hunterzhongme/vllm-orin:0.29
   docker tag ghcr.io/hunterzhongme/vllm-orin:0.29 vllm-orin:0.29
   ```
   Check that the `Digest:` printed by `docker pull` matches `image.digest` in
   `artifacts.lock.json`. The download is about 9.5 GB compressed.
5. **Get the model:** run `scripts/fetch-model.sh` (24 GB). If Hugging Face can't be reached,
   rsync `hub/models--cyankiwi--Qwen3.6-35B-A3B-AWQ-4bit` from the original Orin instead.
6. **Start the server:** run `scripts/serve.sh`. It waits until the model is listed (up to 25
   min). The first start compiles for a few minutes, and later starts reuse `CACHE_DIR`.
7. **Smoke test:** see below.
8. **Point Realtime at it:** in the PoC repo, set `REALTIME_VLM_URL=http://172.17.0.1:8091/v1`
   (from a container) and `REALTIME_VLM_MODEL=qwen3.6-35b-a3b`. See `Realtime/README.md` there.

## Smoke test

```bash
python3 - <<'EOF'
import base64, json, struct, urllib.request, zlib
# 64x64 solid red PNG, built here so the test needs no image file.
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
raw = b"".join(b"\0" + b"\xff\x00\x00" * 64 for _ in range(64))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
img = base64.b64encode(png).decode()
body = {"model": "qwen3.6-35b-a3b", "max_tokens": 32, "messages": [{"role": "user", "content": [
    {"type": "text", "text": "What color is this image? One word."},
    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{img}"}}]}]}
req = urllib.request.Request("http://127.0.0.1:8091/v1/chat/completions", json.dumps(body).encode(),
                             {"Content-Type": "application/json"})
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
print(json.load(opener.open(req, timeout=300))["choices"][0]["message"]["content"])
EOF
```

## Traps we already hit

- **ghcr.io rejects the GitHub CLI login token** (`gh auth token`), even with `write:packages`,
  and returns `denied`. Use a **classic** personal access token (`ghp_…`, scope
  `read:packages`) from `https://github.com/settings/tokens/new`.
- **The agent can't type the token.** `!` commands in Claude Code have no TTY, so
  `read -s` fails with `/dev/tty: No such device or address`. Have the human put the token in
  `~/.ghcr.pat` themselves, then run
  `docker login ghcr.io -u hunterzhongme --password-stdin < ~/.ghcr.pat && rm ~/.ghcr.pat`.
  Never print or `cat` the token.
- **Vim eats the start of the token.** Pasting in normal mode swallowed `gh`, so the file held
  `p_…` and the login was `denied`. Press `i` before pasting. To check the file without showing
  it, use `stat -c %s ~/.ghcr.pat` (a classic token is 41 bytes with the newline) and
  `head -c 4` (should be `ghp_`).
- **`gh auth login` / `refresh` can't open a browser** (the Orin has no display). Enter the code
  it prints at `https://github.com/login/device` on another PC.
- **Unauthenticated `curl https://api.github.com` returns 403.** That is the rate limit, not
  the proxy. ghcr.io answering 401 without credentials means it is reachable.
- **Don't start the image with plain `docker run vllm-orin:0.29`.** The default entrypoint is
  the old Gemma launcher, which exits because its checkpoints don't exist on other machines.
  Always use `scripts/serve.sh`.
- **`serve.sh` deletes the existing `vllm-test` container** (or whatever `NAME` you set) before
  starting. Run one model per Orin, and stop any other vLLM or llama.cpp server first.
- **The image runs with `HF_HUB_OFFLINE=1`,** so the model must be on disk before `serve.sh`.
  `fetch-model.sh` turns offline mode off just for the download.
- **Behind the proxy, use `--noproxy '*'` for local curl,** otherwise requests to localhost go
  to the proxy.
- **After pushing or pulling, `docker logout ghcr.io`** if the machine is shared. Docker stores
  the token unencrypted in `~/.docker/config.json`.
