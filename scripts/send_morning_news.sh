#!/usr/bin/env bash
set -euo pipefail

CLI_BIN="$HOME/.tencent-news-cli/bin/tencent-news-cli"

if [ -z "${WECOM_WEBHOOK_URL:-}" ]; then
  echo "WECOM_WEBHOOK_URL is not set"
  exit 1
fi

if [ -z "${TENCENT_NEWS_API_KEY:-}" ]; then
  echo "TENCENT_NEWS_API_KEY is not set"
  exit 1
fi

NEWS_CONTENT="$("$CLI_BIN" morning 2>&1 \
  | sed -E $'s/\x1B\\[[0-9;]*[A-Za-z]//g' \
  | tr -d '\r' \
  | sed '/^[[:space:]]*$/d' \
  | iconv -f utf-8 -t utf-8 -c)"

if [ -z "$NEWS_CONTENT" ]; then
  NEWS_CONTENT="今日早报拉取失败：返回为空"
fi

export WECOM_WEBHOOK_URL
export NEWS_CONTENT

python3 <<'PY'
import json
import os
import sys
import time
import urllib.request

webhook = os.environ["WECOM_WEBHOOK_URL"]
news = os.environ["NEWS_CONTENT"]

prefix = "今日早报\n\n"
full_text = prefix + news

# 单条消息保守分段，避免客户端显示不全
max_len = 1200

parts = []
start = 0
while start < len(full_text):
    end = min(start + max_len, len(full_text))
    if end < len(full_text):
        split_pos = full_text.rfind("\n", start, end)
        if split_pos > start:
            end = split_pos

    part = full_text[start:end].strip()
    if part:
        parts.append(part)
    start = end

if not parts:
    parts = ["今日早报拉取失败：内容为空"]

for i, part in enumerate(parts, 1):
    if len(parts) > 1:
        content = f"【第{i}/{len(parts)}段】\n{part}"
    else:
        content = part

    payload = {
        "msgtype": "text",
        "text": {
            "content": content
        }
    }

    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        webhook,
        data=data,
        headers={"Content-Type": "application/json"}
    )

    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            print(body)
    except Exception as e:
        print(f"Send failed on part {i}: {e}", file=sys.stderr)
        raise

    # 避免过快发送
    time.sleep(1)
PY
