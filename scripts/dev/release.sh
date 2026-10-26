#!/usr/bin/env bash
# 发版一条命令：校验 → 升版本 → 写说明检查 → 全量门禁 → 建 PR → 给后续步骤。
#
# 为什么需要（2026-10-26 成本复盘 O4）：发版流程有 6 步散在 `docs/iteration-flow.md` §5，
# 每次都要人工对照（版本号递增、notes 文件、`--full`/`--ui`、dry-run、产物断言、父仓库 bump），
# 0.1.5 就是因为漏了"产物断言"而发了 hotfix。这个脚本把能自动的都自动，不能自动的明确列出来。
#
# 用法：
#   scripts/dev/release.sh --version 0.1.7 --plan     # 只打印将要做什么（不改任何文件）
#   scripts/dev/release.sh --version 0.1.7            # 升版本 + 全量门禁 + 建 PR
#   scripts/dev/release.sh --version 0.1.7 --skip-gates   # 跳过门禁（仅调试脚本时用）
#
# 之后仍需人工/半自动的三步（脚本结束时会打印）：
#   1. 合并 PR（CI 绿后）
#   2. `gh workflow run release-app.yml -f dry_run=true` 演练一次
#   3. `gh workflow run release-app.yml` 真发，然后按提示核验产物 + bump 父仓库
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
XCCONFIG="OrzMC/Configuration/Config.xcconfig"

VERSION=""
PLAN=0
SKIP_GATES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:?}"; shift 2 ;;
        --plan) PLAN=1; shift ;;
        --skip-gates) SKIP_GATES=1; shift ;;
        -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

[[ -n "$VERSION" ]] || die "必须给 --version（例：--version 0.1.7）"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本号格式应为 X.Y.Z（拿到：${VERSION}）"

# ── 1. 前置检查 ───────────────────────────────────────────────────────────────
step "前置检查"
current_marketing="$(sed -n 's/^MARKETING_VERSION=//p' "$XCCONFIG")"
current_build="$(sed -n 's/^CURRENT_PROJECT_VERSION=//p' "$XCCONFIG")"
[[ -n "$current_marketing" && -n "$current_build" ]] || die "读不到 $XCCONFIG 里的版本"
new_build=$((current_build + 1))

if [[ "$(printf '%s\n%s\n' "$current_marketing" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]] \
   || [[ "$VERSION" == "$current_marketing" ]]; then
    die "新版本 $VERSION 必须大于当前 $current_marketing"
fi
ok "版本：$current_marketing ($current_build) → $VERSION ($new_build)"

NOTES="docs/release-notes/$VERSION.md"
[[ -f "$NOTES" ]] || die "缺少发版说明：${NOTES}（用户视角：改了什么 / 要不要手动做什么 / 已知问题）"
notes_size="$(wc -c < "$NOTES" | tr -d ' ')"
[[ "$notes_size" -ge 400 ]] || die "$NOTES 只有 ${notes_size} 字节，太短，不像给用户看的说明"
ok "发版说明：${NOTES}（${notes_size} 字节）"

if [[ "$PLAN" -eq 0 ]]; then
    branch="$(git rev-parse --abbrev-ref HEAD)"
    [[ "$branch" == "main" ]] || die "请在 main 上发版（当前：${branch}）"
    [[ -z "$(git status --porcelain)" ]] || die "工作区不干净，先提交或 stash"
    git fetch --quiet origin
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "本地 main 与 origin/main 不一致，先 pull"
    ok "仓库状态：main / clean / 与远端一致"
else
    printf '  （--plan：跳过分支/工作区检查）\n'
fi

# ── 2. 改版本号 ───────────────────────────────────────────────────────────────
step "改版本号"
if [[ "$PLAN" -eq 1 ]]; then
    printf '  将把 %s 改成：\n    MARKETING_VERSION=%s\n    CURRENT_PROJECT_VERSION=%s\n' "$XCCONFIG" "$VERSION" "$new_build"
else
    python3 - "$XCCONFIG" "$VERSION" "$new_build" <<'PY2'
import pathlib, re, sys
path, version, build = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
s = p.read_text()
s = re.sub(r"^MARKETING_VERSION=.*$", f"MARKETING_VERSION={version}", s, flags=re.M)
s = re.sub(r"^CURRENT_PROJECT_VERSION=.*$", f"CURRENT_PROJECT_VERSION={build}", s, flags=re.M)
p.write_text(s)
PY2
    ok "已写入 $XCCONFIG"
fi

# ── 3. 门禁 ───────────────────────────────────────────────────────────────────
if [[ "$SKIP_GATES" -eq 1 ]]; then
    step "门禁（已跳过 --skip-gates）"
elif [[ "$PLAN" -eq 1 ]]; then
    step "门禁（--plan：将依次执行）"
    printf '  ./scripts/dev/check.sh --fast\n  ./scripts/dev/check.sh --full\n  ./scripts/dev/check.sh --ui\n'
else
    step "门禁 1/3：静态 + 包单测 + 应用测试 + macOS 构建"
    ./scripts/dev/check.sh --fast >/dev/null
    ./scripts/dev/check.sh --full | tail -3
    step "门禁 2/3：模拟器 UI 验收"
    ./scripts/dev/check.sh --ui | tail -3
    step "门禁 3/3：真机 UI（可选，需要数据线；没有设备时跳过）"
    device="$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected/ {print $3; exit}')"
    if [[ -n "$device" ]]; then
        ./scripts/dev/run-ios-ui-tests.sh --device "$device" --detach | tail -5
    else
        printf '  （没有已连接的真机，跳过；发版前建议补一次）\n'
    fi
fi

# ── 4. 提交 + PR ─────────────────────────────────────────────────────────────
step "提交 + 建 PR"
if [[ "$PLAN" -eq 1 ]]; then
    printf '  将创建分支 release/%s、提交、推送并 gh pr create\n' "$VERSION"
    printf '\n后续（人工/半自动）：\n'
    printf '  1. 合并 PR（CI 绿）\n  2. gh workflow run release-app.yml -f dry_run=true\n  3. gh workflow run release-app.yml\n'
    exit 0
fi

git switch -c "release/$VERSION" >/dev/null
git add "$XCCONFIG" "$NOTES"
git commit -q -F - <<EOF2
chore(release): $VERSION ($new_build)

用户视角的发版说明见 \`$NOTES\`。
EOF2
git push -u origin "release/$VERSION" >/dev/null
gh pr create --base main --head "release/$VERSION" \
    --title "chore(release): $VERSION ($new_build)" \
    --body "版本 \`$current_marketing ($current_build)\` → **\`$VERSION ($new_build)\`**；发版说明 \`$NOTES\`。全量门禁已本地通过（静态 / 包单测 / 应用测试 / macOS + iOS 构建 / 协议联调 / 模拟器 UI / 真机 UI）。" >/dev/null
ok "PR 已创建：release/$VERSION"

cat <<EOF2

接下来的三步（脚本不代劳）：
  1) 等 CI 绿后合并：            gh pr merge release/$VERSION --squash --delete-branch
  2) 发版演练（不发 Release）：   gh workflow run release-app.yml -f dry_run=true
  3) 真发：                      gh workflow run release-app.yml
然后核验产物（别只看绿了）：
  gh release view $VERSION --json assets --jq '.assets[].name'
  # 下载 zip → codesign -dv / lipo -archs（期望 x86_64 arm64）/ spctl -a -vv --type execute
最后在父仓库 bump \`swift/app\` 指针并更新 HANDOFF / RELEASES.md。
EOF2
