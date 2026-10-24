#!/usr/bin/env python3
"""修 `build-for-testing` 生成的 `.xctestrun` 里的 **UI 测试目标 App 路径**。

背景：本项目 `OrzMC.xcodeproj/project.pbxproj` 是手工维护的（没有用 Xcode 的
文件系统同步组）。Xcode 27 生成的 xctestrun 里会出现：

    UITargetAppPath = __TESTROOT__/Debug-iphoneos/OrzMC     ← 少了 ".app"

结果是跑真机 UI 测试时报
`The bundle identifier for OrzMC couldn't be read. No such file or directory: …/Debug-iphoneos/OrzMC`，
或者 runner 起不来（code 74 / testmanagerd 拒绝 dtxproxy 通道）。

这个脚本把 `UITargetAppPath` 补成真实的 `.app` 路径，并从 App 的 Info.plist 里
补上 `UITargetAppBundleIdentifier`。只改这两个字段，其他原样保留。

用法：
    patch-xctestrun.py <xctestrun> [--app <OrzMC.app 路径>]
"""

from __future__ import annotations

import argparse
import plistlib
import sys
from pathlib import Path


def find_app(xctestrun: Path) -> Path:
    """按文件名里的平台（iphoneos / iphonesimulator）去找对应的 Debug-<platform>/*.app。"""
    root = xctestrun.parent
    platform = next(
        (p for p in ("iphonesimulator", "iphoneos") if p in xctestrun.name), None
    )
    patterns = [f"Debug-{platform}/*.app"] if platform else ["Debug-*/*.app"]
    candidates = [
        p
        for pattern in patterns
        for p in root.glob(pattern)
        if not p.name.endswith("-Runner.app") and "xctest" not in p.name.lower()
    ]
    if len(candidates) == 1:
        return candidates[0]
    # 兜底：名字里带 OrzMC 的那个
    named = [p for p in candidates if "OrzMC" in p.name]
    if len(named) == 1:
        return named[0]
    raise SystemExit(f"✗ 无法确定目标 App：候选 {[p.name for p in candidates]}")


def ui_test_targets(data: dict) -> list[dict]:
    """兼容两种 xctestrun 格式。

    * 老格式（Xcode 12 起）：`{"TestConfigurations": [{"TestTargets": [...]}]}`
    * 新格式（Xcode 15+）：顶层就是各测试目标的名字，附带 `__xctestrun_metadata__`
    """
    if "TestConfigurations" in data:
        return [t for c in data["TestConfigurations"] for t in c.get("TestTargets", [])]
    return [
        value
        for key, value in data.items()
        if key != "__xctestrun_metadata__" and isinstance(value, dict)
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("xctestrun", type=Path)
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()

    path: Path = args.xctestrun
    if not path.is_file():
        print(f"✗ 找不到 {path}", file=sys.stderr)
        return 1

    app = args.app or find_app(path)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    bundle_id = info.get("CFBundleIdentifier")
    if not bundle_id:
        print(f"✗ {app}/Info.plist 里没有 CFBundleIdentifier", file=sys.stderr)
        return 1

    data = plistlib.loads(path.read_bytes())
    fixed = 0
    for target in ui_test_targets(data):
        if True:
            if not target.get("IsUITestBundle"):
                continue
            wanted = f"__TESTROOT__/{app.parent.name}/{app.name}"
            if target.get("UITargetAppPath") != wanted:
                print(f"· UITargetAppPath: {target.get('UITargetAppPath')!r} → {wanted!r}")
                target["UITargetAppPath"] = wanted
                fixed += 1
            if target.get("UITargetAppBundleIdentifier") != bundle_id:
                print(f"· UITargetAppBundleIdentifier: {target.get('UITargetAppBundleIdentifier')!r} → {bundle_id!r}")
                target["UITargetAppBundleIdentifier"] = bundle_id
                fixed += 1

    if fixed:
        path.write_bytes(plistlib.dumps(data))
        print(f"✓ 已修 {path.name}（{fixed} 处）")
    else:
        print(f"✓ {path.name} 无需修改")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
