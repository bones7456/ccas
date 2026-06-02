#!/usr/bin/env bash
#
# ┌──────────────────────────────────────────────────────────────────┐
# │  ⚠️  必读：撞到 /login 提示时第一时间跑这个脚本                  │
# │                                                                  │
# │  在跑脚本之前，绝对不要做以下任何操作 —— 都会覆盖现场：          │
# │    ✗ 不要 /login                                                 │
# │    ✗ 不要用 CCAS 切换账号（switch-away 会把 live 快照到 backup） │
# │    ✗ 不要重启 Claude Code                                        │
# │                                                                  │
# │  跑完脚本、把输出贴出来之后，再做任何恢复操作。                  │
# └──────────────────────────────────────────────────────────────────┘
#
# Capture Claude Code's live keychain and a CCAS account backup side-by-side
# when Claude Code unexpectedly prompts /login after a CCAS switch.
#
# Usage:
#   scripts/diagnose_login_loss.sh <account_number> <email>
# Example:
#   scripts/diagnose_login_loss.sh 3 you@example.com

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <account_number> <email>" >&2
    exit 1
fi

cat >&2 <<'WARN'
⚠️  现场保护提醒：
    跑完之前不要 /login、不要切换账号、不要重启 Claude Code。
    任何写 keychain 的操作都会覆盖案发现场。

WARN

NUMBER="$1"
EMAIL="$2"

python3 - "$NUMBER" "$EMAIL" <<'PY'
import json, subprocess, sys

number, email = sys.argv[1], sys.argv[2]

def shape(blob, label):
    try:
        d = json.loads(blob)
    except Exception as e:
        print(f"{label}: parse error {e}\n")
        return
    o = d.get("claudeAiOauth", {})
    print(f"=== {label} ===")
    print("top-level keys :", sorted(d.keys()))
    print("claudeAiOauth  :", sorted(o.keys()))
    print("scopes         :", o.get("scopes"))
    print("subscriptionType:", o.get("subscriptionType"))
    print("rateLimitTier  :", o.get("rateLimitTier"))
    print("clientId       :", o.get("clientId"))
    print("expiresAt      :", o.get("expiresAt"))
    print("accessToken len:", len(o.get("accessToken", "")))
    print("refreshToken len:", len(o.get("refreshToken", "")))
    print()

def read_pw(service, account=None):
    cmd = ["security", "find-generic-password", "-s", service]
    if account:
        cmd += ["-a", account]
    cmd += ["-w"]
    return subprocess.check_output(cmd, text=True).strip()

shape(read_pw("Claude Code-credentials"), "LIVE (Claude Code)")
shape(read_pw("li.luy.ccas.accounts", f"account-{number}-{email}"),
      f"BACKUP #{number} (CCAS)")
PY
