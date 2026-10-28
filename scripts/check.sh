#!/usr/bin/env bash
# 提交前本地自检：编译 + 单测 + e2e。CI 跑的是同样的东西。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== build"
swift build

echo "== test"
swift test

echo "== e2e"
.build/debug/Manatee --e2e
