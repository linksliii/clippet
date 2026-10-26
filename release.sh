#!/bin/bash
# 一键发布：构建 → 打包 → 测试 → 提交 → 推送 → 上传产物
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

REPO="linksliii/clippet"
ASSET="Clippet.app.zip"
VERSION=$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' build.sh)
TAG="v${VERSION}"
MSG="${1:-release: ${TAG}}"

echo "==> 1/6 测试"
swift build >/dev/null 2>&1
if ! .build/debug/Clippet --selftest >/tmp/clippet-tests.log 2>&1; then
    tail -20 /tmp/clippet-tests.log
    echo "测试未通过，中止发布"; exit 1
fi
echo "    $(grep -c '  ok ' /tmp/clippet-tests.log) 项通过"

echo "==> 2/6 构建 release"
./build.sh release >/dev/null 2>&1
echo "    binary: $(ls -lh build/Clippet.app/Contents/MacOS/Clippet | awk '{print $5}')"

echo "==> 3/6 打包产物"
mkdir -p dist
rm -f "dist/$ASSET"
ditto -c -k --keepParent build/Clippet.app "dist/$ASSET"
echo "    $ASSET: $(ls -lh "dist/$ASSET" | awk '{print $5}')"

echo "==> 4/6 提交"
git add -A
if git diff --cached --quiet; then
    echo "    无变更，跳过提交"
else
    git -c user.name="linksli" -c user.email="chengzeli@pony.ai" commit -q -m "$MSG"
    echo "    $(git log --oneline -1)"
fi

echo "==> 5/6 推送"
git push origin main 2>&1 | tail -1

echo "==> 6/6 上传到 Release $TAG"
TOKEN=$(sed -nE 's#https://([^:]+):([^@]+)@github\.com#\2#p' ~/.git-credentials | head -1)
if [ -z "$TOKEN" ]; then
    echo "    未找到 GitHub 凭据，跳过上传"; exit 0
fi
API="https://api.github.com/repos/$REPO"
RID=$(curl -s -u "linksliii:$TOKEN" "$API/releases/tags/$TAG" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
if [ -z "$RID" ]; then
    RID=$(curl -s -X POST -u "linksliii:$TOKEN" -H "Accept: application/vnd.github+json" \
        "$API/releases" -d "{\"tag_name\":\"$TAG\",\"name\":\"Clippet $VERSION\",\"body\":\"见 README\"}" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))')
fi
OLD=$(curl -s -u "linksliii:$TOKEN" "$API/releases/$RID/assets" | python3 -c "import sys,json;print(next((a['id'] for a in json.load(sys.stdin) if a['name']=='$ASSET'),''))" 2>/dev/null)
[ -n "$OLD" ] && curl -s -X DELETE -u "linksliii:$TOKEN" "$API/releases/assets/$OLD" >/dev/null
CODE=$(curl -s -o /tmp/clippet-asset.json -w "%{http_code}" -X POST -u "linksliii:$TOKEN" \
    -H "Content-Type: application/zip" --data-binary "@dist/$ASSET" \
    "https://uploads.github.com/repos/$REPO/releases/$RID/assets?name=$ASSET")
echo "    HTTP $CODE — $(python3 -c 'import json;d=json.load(open("/tmp/clippet-asset.json"));print(d.get("browser_download_url",""))' 2>/dev/null)"
echo "==> 完成"
