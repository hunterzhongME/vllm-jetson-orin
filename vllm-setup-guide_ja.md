# vLLM 導入手順（Jetson AGX Orin / TSUMUGi）

llama.cpp で動かしていた LLM を、vLLM（`qwen3.6-35b-a3b`）に置き換える手順です。
この Orin で実際に行った作業をもとに、順番どおりに実行できるようにまとめました。

- 作業日: 2026-10-28
- 元になった資料: `/mnt/ssd/vllm-jetson-orin/HANDOFF.md` と `README.md`
- 完成の目安: `curl --noproxy '*' localhost:8091/v1/models` が `qwen3.6-35b-a3b` を返し、赤い画像のテストが「Red」と答える

## 0. 先に知っておくこと

| 項目 | 内容 |
| --- | --- |
| 動く機種 | AGX Orin 64GB、JetPack 6.2（L4T R36.4.x）だけ。他の機種や版では動かない |
| 台数 | 1 台の Orin で動かすモデルは 1 つ。llama.cpp と vLLM は同時に動かさない（GPU メモリとポート 8091 が足りない） |
| イメージ | `ghcr.io/hunterzhongme/vllm-orin:0.29`（圧縮 9.5 GB）。**作り直さない**（数時間かかり、不要） |
| モデル | `cyankiwi/Qwen3.6-35B-A3B-AWQ-4bit`（24 GB） |
| 必要な空き容量 | 約 60 GB。ルート（eMMC）は小さいので、SSD に置く |
| 所要時間 | イメージ取得 約 40 分、モデル取得 約 25 分（回線による）、初回起動 数分 |

この Orin での置き場所（`/mnt/ros_data` がないため変更した）:

| 用途 | 場所 |
| --- | --- |
| モデル（`HF_DIR`） | `/mnt/ssd/llama/vllm/hf` |
| コンパイルのキャッシュ（`CACHE_DIR`） | `/mnt/ssd/llama/vllm/cache` |
| systemd のユニット（控え） | `/mnt/ssd/llama/vllm/vllm-orin.service` |
| スクリプト一式 | `/mnt/ssd/vllm-jetson-orin`（root 所有。書き込めない） |

## 1. ホストを確かめる

```bash
cd /mnt/ssd/vllm-jetson-orin
scripts/check-host.sh
```

- ボード、L4T、メモリ、nvidia ランタイムが `ok` になること。合わなければここで止める（回避策はない）。
- `free space near /mnt/ros_data/hf` だけが `FAIL` でも、置き場所を変えるので問題ない（手順 2）。
- 空きを確認する: `df -h /mnt/ssd`（Docker の保存先も `/mnt/ssd/docker`）。

## 2. 置き場所を作る

```bash
mkdir -p /mnt/ssd/llama/vllm/hf /mnt/ssd/llama/vllm/cache
```

以降のスクリプトでは、次の 2 つの環境変数を毎回付ける。

```bash
export HF_DIR=/mnt/ssd/llama/vllm/hf
export CACHE_DIR=/mnt/ssd/llama/vllm/cache
```

> `export` は新しい端末では消える。端末を開き直したら、もう一度実行する。

## 3. ghcr.io にログインする

イメージは非公開なので、人が操作する必要がある（エージェントは token を入力できない）。

1. https://github.com/settings/tokens/new で **classic** のトークンを作る。
   - スコープは `read:packages` だけ。`ghp_` で始まる。
   - `gh auth token` で得たトークンは**使えない**（`denied` になる）。
2. エディタでファイルに貼り付ける。vim は **`i` を押してから**貼り付ける（押さないと先頭が消える）。

   ```bash
   umask 077; vim ~/.ghcr.pat
   ```

3. 中身を表示せずに確かめる。

   ```bash
   stat -c %s ~/.ghcr.pat; head -c 4 ~/.ghcr.pat    # 41 と ghp_ になること
   ```

4. ログインして、ファイルを消す。

   ```bash
   docker login ghcr.io -u hunterzhongme --password-stdin < ~/.ghcr.pat && rm ~/.ghcr.pat
   ```

   `Login Succeeded` と出れば成功。トークンを `cat` や `echo` で表示しない。

## 4. イメージを取得する

```bash
docker pull ghcr.io/hunterzhongme/vllm-orin:0.29
docker tag ghcr.io/hunterzhongme/vllm-orin:0.29 vllm-orin:0.29
```

1. 終わりに表示される `Digest:` が、`/mnt/ssd/vllm-jetson-orin/artifacts.lock.json` の `image.digest`
   （`sha256:f410a1d6eb6dce9c6e5e79d073b8f91063eb349074545433e01700505af4a44e`）と一致することを確かめる。
2. `docker images vllm-orin:0.29` で表示されること。
3. 取得中の進み具合: `lan1` の受信量を見る（約 4 MB/s で 40 分ほど）。`unauthorized` と出たら手順 3 をやり直す
   （Docker の設定はユーザーごと。`mic-733ao` でログインしたか確かめる）。

## 5. モデルを取得する

```bash
cd /mnt/ssd/vllm-jetson-orin
HF_DIR=/mnt/ssd/llama/vllm/hf scripts/fetch-model.sh
```

- 24 GB、22 ファイル。途中で止まっても同じコマンドで続きから取得する。
- 進み具合: `du -sh /mnt/ssd/llama/vllm/hf`。始めの数分は 1 MB/s 前後で遅く、その後 17 MB/s 程度に上がった。
- 「`✓ Downloaded`」が出れば完了。
- Hugging Face に届かないときは、元の Orin から rsync する:
  `rsync -aP <元のOrin>:/mnt/ros_data/hf/hub/models--cyankiwi--Qwen3.6-35B-A3B-AWQ-4bit /mnt/ssd/llama/vllm/hf/hub/`

> イメージは `HF_HUB_OFFLINE=1` で動く。起動前にモデルがディスクにあること。

## 6. llama.cpp を止める

vLLM は GPU メモリを約 37 GiB 使い、ポート 8091 も使う。この Orin では llama.cpp が両方をふさいでいた。

| サービス | 役割 | ポート |
| --- | --- | --- |
| `llama-server.service` | チャット / VLM（約 17.7 GB を使用） | 8090 |
| `llama-embedding.service` | 埋め込み（`ruri-v3-310m`） | 8091 |

```bash
systemctl stop llama-embedding.service llama-server.service
ss -ltn | grep 8091      # 何も出なければ空いている
```

> 止めると、これらに依存する機能が使えなくなる。他の人が使っていないか確かめてから止める。
> 止めないと `address already in use`（ポート）や `Free memory ... is less than desired GPU memory utilization`（メモリ）で起動に失敗する。

## 7. vLLM を起動する

```bash
cd /mnt/ssd/vllm-jetson-orin
HF_DIR=/mnt/ssd/llama/vllm/hf CACHE_DIR=/mnt/ssd/llama/vllm/cache scripts/serve.sh
```

- `qwen3.6-35b-a3b ready on :8091` と出るまで待つ（最大 25 分。初回は torch.compile と CUDA graph で数分かかる）。
- 2 回目以降は `CACHE_DIR` のキャッシュで速くなる。
- `serve.sh` は同名のコンテナ `vllm-test` を**削除してから**作り直す。
- 素の `docker run vllm-orin:0.29` は使わない（古い Gemma 用の起動処理が動いて終了する）。
- 失敗したとき: `docker logs vllm-test 2>&1 | grep -i error | tail`

## 8. 動作確認（スモークテスト）

```bash
curl --noproxy '*' localhost:8091/v1/models
```

`qwen3.6-35b-a3b` を含む一覧が返ること。続いて、赤い画像を見せて色を聞く。

```bash
python3 - <<'EOF'
import base64, json, struct, urllib.request, zlib
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
raw = b"".join(b"\0" + b"\xff\x00\x00" * 64 for _ in range(64))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
img = base64.b64encode(png).decode()
body = {"model": "qwen3.6-35b-a3b", "max_tokens": 32, "messages": [{"role": "user", "content": [
    {"type": "text", "text": "What color is this image? One word."},
    {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{img}"}}]}]}
req = urllib.request.Request("http://127.0.0.1:8091/v1/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
print(json.load(opener.open(req, timeout=300))["choices"][0]["message"]["content"])
EOF
```

`Red` と表示されれば成功。プロキシ（Zscaler）の下では、ローカルへの curl に **`--noproxy '*'`** が要る
（付けないと 403 が返る）。

## 9. ログアウトする

共有マシンでは、Docker がトークンを `~/.docker/config.json` に平文で保存するので、取得が終わったら消す。

```bash
docker logout ghcr.io
```

## 10. 再起動後も自動で動くようにする（systemd）

llama.cpp を起動時の自動実行から外し、vLLM を入れる。ユニットファイルは作成済み
（`/mnt/ssd/llama/vllm/vllm-orin.service`）。**`sudo`（パスワード）が必要なので、人が実行する。**

```bash
sudo cp /mnt/ssd/llama/vllm/vllm-orin.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl disable llama-server.service llama-embedding.service
sudo systemctl enable vllm-orin.service
```

- `--now` は付けない。すでに `vllm-test` が動いているため、起動し直すとモデルを読み込み直してしまう。
- ユニットは `Conflicts=` で llama.cpp の 2 つと同時に動かないようにしている。
- 確認:

  ```bash
  systemctl is-enabled vllm-orin.service llama-server.service llama-embedding.service
  # → enabled / disabled / disabled
  ```

- 再起動すると、`serve.sh` が起動して数分後に使える。確認は手順 8 の `curl`。
  Docker のサービスたち（core など）は vLLM を待たずに起動するため、その間の LLM 呼び出しは失敗する（許容している）。

## 11. TSUMUGi（アプリ）を vLLM に向ける

対象の設定は `/mnt/ssd/Project/DMSHI-PALette-PoC/build/.env`（git 管理外）。

### 11-1. `.env` を書き換える

| 変数 | 変更前 | 変更後 |
| --- | --- | --- |
| `LLM_MODEL_ID` | `/mnt/ssd/llama/models/active-model.gguf` | `qwen3.6-35b-a3b` |
| `LLM_BASE_URL` | `http://host.docker.internal:8090/v1` | `http://host.docker.internal:8091/v1` |
| `CONTACT_SHEET_PROVIDER` | （未設定） | `openai-compat` |
| `CONTACT_SHEET_MODEL_ID` | （未設定） | `qwen3.6-35b-a3b` |
| `GLOSSARY_OPENSEARCH_URL` | `http://opensearch:9200` | （空にする） |

`GLOSSARY_OPENSEARCH_URL` を空にするのは、埋め込みモデルを使わない間、用語集の意味検索と同期を止めるため。
llama.cpp の埋め込みサーバーを止めたので、そのままだと用語集の編集時に同期のエラーが出る。

### 11-2. compose を 1 行直す

空の値が既定値で埋め戻されないようにする。`build/docker-compose-ai-box.yml` の glossary の行:

```yaml
# 変更前
- GLOSSARY_OPENSEARCH_URL=${GLOSSARY_OPENSEARCH_URL:-http://opensearch:9200}
# 変更後（コロンを外す）
- GLOSSARY_OPENSEARCH_URL=${GLOSSARY_OPENSEARCH_URL-http://opensearch:9200}
```

これは git 管理のファイルなので、差分に出る（`git diff`）。

### 11-3. コンテナを作り直す

イメージのビルドは**要らない**（設定は起動時に読まれる）。

```bash
cd /mnt/ssd/Project/DMSHI-PALette-PoC/build
docker compose -f docker-compose-ai-box.yml -f docker-compose.jetson.yml up -d --no-deps \
  ai-agent core-api measure-api misc-api glossary-api
```

compose のサービス名は `core-api` のように `-api` 付き。コンテナ名（`core`、`measure`、`glossary` など）とは違う。

### 11-4. 確かめる

```bash
docker ps --format '{{.Names}} {{.Status}}'          # すべて healthy
for c in ai-agent core measure misc; do docker exec $c env | grep '^LLM_BASE_URL'; done
# どれも http://host.docker.internal:8091/v1
docker exec ai-agent env | grep '^CONTACT_SHEET_PROVIDER\|^CONTACT_SHEET_MODEL_ID'
curl --noproxy '*' -s -o /dev/null -w '%{http_code}\n' localhost:5173     # 200
```

ブラウザで `http://<Orin の IP>:5173` を開き直し、AI を使う機能を 1 つ試す。

## 12. Realtime（組立ミス検知）を vLLM に向ける

`/mnt/ssd/Project/DMSHI-PALette-PoC/Realtime/configs/` の次の 4 ファイルで、`models.vlm` を書き換えた。

- `sim_packaging_vlm.json`
- `sim_packaging_layout.json`
- `sim_filling_vlm.json`
- `sim_filling_vlm_frames.json`

```json
"vlm": {
  "url": "http://172.17.0.1:8091/v1/chat/completions",
  "model": "qwen3.6-35b-a3b",
  "timeout_s": 60
}
```

- `experiments/` と `benchmark/` の下は過去の実験の記録なので変えない。
- 設定ファイルは `-v $PWD/Realtime:/realtime` で渡すので、次の実行から有効になる（ビルド不要）。
- 環境変数 `REALTIME_VLM_URL` と `REALTIME_VLM_MODEL` で、実行ごとに上書きもできる。
  コンテナからホストへは `172.17.0.1` を使う。

## 13. 元に戻す

1. vLLM を止める: `docker stop vllm-test`（自動起動を外すなら `sudo systemctl disable vllm-orin.service`）。
2. llama.cpp を戻す:

   ```bash
   sudo systemctl enable --now llama-server.service
   # 埋め込みも使うとき（vLLM とはポート 8091 がぶつかるので、vLLM を止めてから）
   sudo systemctl enable --now llama-embedding.service
   ```

3. `.env` を手順 11-1 の「変更前」に戻し、手順 11-3 でコンテナを作り直す。

## 14. 困ったとき

| 症状 | 原因と対処 |
| --- | --- |
| `docker pull` が `unauthorized` / `denied` | classic の PAT（`ghp_`、`read:packages`）で、`mic-733ao` ユーザーのまま `docker login` する。`gh` のトークンは不可 |
| vim で貼ったトークンが `denied` | 先頭が欠けている。`i` を押してから貼る。`head -c 4` が `ghp_` か確かめる |
| `mkdir ... 許可がありません` | `/mnt/ssd` 直下と `/mnt/ssd/vllm-jetson-orin` は root 所有。書き込めるのは `/mnt/ssd/llama` や `/mnt/ssd/Project` の下 |
| `address already in use`（8091） | llama.cpp の埋め込みサーバーが使っている。手順 6 |
| `Free memory ... less than desired GPU memory utilization` | 他のプロセスが GPU を使っている（llama.cpp のチャットなど）。手順 6 |
| ローカルへの curl が 403 | Zscaler のプロキシ。`--noproxy '*'` を付ける |
| 起動に時間がかかる | 初回の torch.compile。`docker logs -f vllm-test`。2 回目以降はキャッシュで速い |
| 用語集の意味検索が 503 | 設定どおり（埋め込みを止めている）。使いたいなら、埋め込みサーバーを別に立てて手順 11-1 を戻す |
| 画面の AI 機能が失敗する | `docker exec ai-agent env \| grep LLM_` が 8091 か確かめる。起動直後は vLLM の読み込み待ち |

## 15. 今の制限（了承済み）

- `--max-num-seqs 1`、KV キャッシュ 4 GiB、1 リクエストあたり画像 64 枚まで。同時の要求は順番待ちになる。
- `enable_thinking:false` が全呼び出しに効く（構造化出力向き）。
- 用語集の意味検索（埋め込み）は使えない。再開するには別の埋め込みサーバーが要る。
- コンテナは vLLM の起動完了を待たない。再起動後の数分は AI 機能が失敗する。
- 画像キャプション（`GLOSSARY_IMAGE_CAPTION_ENABLED`）は無効のまま。有効にすると Bedrock が既定の接続先になる。
