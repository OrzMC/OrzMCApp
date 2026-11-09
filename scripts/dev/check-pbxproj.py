#!/usr/bin/env python3
"""校验 `OrzMC.xcodeproj/project.pbxproj`：

1. **登记完整**：`OrzMC/` 下每个 `.swift` 都能通过某条 `PBXFileReference` 解析回自己
   （否则干净构建会失败，或代码静默地没被编译）。
2. **没有悬空引用**：所有 `PBXFileReference` / `PBXGroup` 的路径在磁盘上都存在
   （否则 Xcode 项目导航器里显示成红色 —— 2026-11-09 清掉了 26 个这种历史残留）。

为什么需要它：这个工程用的是**传统 PBXGroup（逐文件登记）**，不是 Xcode 16 的
同步文件夹。新增 `.swift` 文件后如果忘了登记：

* 本地增量构建**不会报错**（旧的目标文件还在，Swift 的按文件增量编译不会重编引用方），
* CI 若恰好命中缓存也可能绿，
* 但**干净构建会失败**，或者更糟——文件里的代码静默地没有被编译进去。

这个坑真实发生过两次（`ExarotonServerCard.swift`、`EscapeClosesWindow.swift`）。

实现说明：CI 的 `split` job 跑在 **ubuntu** 上，没有 `plutil`；这里用一个最小的
OpenStep plist 解析（只取 `isa/path/sourceTree/children`），不引入新依赖。

用法：
    python3 scripts/dev/check-pbxproj.py            # 仓库根目录跑
退出码 1 表示有文件没登记，或存在悬空引用。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "OrzMC.xcodeproj" / "project.pbxproj"

# 只检查应用目标下的源码目录（Tests / Sources 是 SwiftPM，自动收录）。
SOURCE_DIRS = [
    ROOT / "OrzMC",
]

# 这些 sourceTree 指向构建产物 / SDK，不在仓库里，跳过存在性检查。
SKIP_SOURCE_TREES = {
    "BUILT_PRODUCTS_DIR",
    "SDKROOT",
    "DEVELOPER_DIR",
    "PLATFORM_DIR",
}

# 行式解析（不用跨行正则）：pbxproj 有两种对象写法 ——
#   · 单行：`		<ID> /* name */ = {isa = ...; ... };`
#   · 多行：`		<ID> /* name */ = {` … `		};`
# 根 group 这类对象**没有**注释，所以注释部分是可选的。
# 早期版本用跨行正则，单行对象会被"下一行"继续吞掉（把后面的 build phase 当成自己的 body），
# 结果文件明明登记了却报"没登记"—— 别再改回去。
OBJECT_START_RE = re.compile(r"^\t\t([0-9A-F]{24})(?: /\* .*? \*/)? = \{(.*)$")
MALFORMED_ID_RE = re.compile(r"^\t\t([0-9A-F]{8,}) (?:/\*|=\{)")
ISA_RE = re.compile(r"\bisa = (\w+);")
PATH_RE = re.compile(r"\bpath = (?:\"([^\"]*)\"|([^;\n]+));")
TREE_RE = re.compile(r"\bsourceTree = (?:\"([^\"]*)\"|([^;\n]+));")
CHILDREN_RE = re.compile(r"\bchildren = \((.*?)\);", re.DOTALL)
MAIN_GROUP_RE = re.compile(r"\bmainGroup = ([0-9A-F]{24});")
ID_RE = re.compile(r"([0-9A-F]{24})")


def parse_objects(text: str) -> dict[str, dict]:
    """pbxproj → `id -> {isa, path, sourceTree, children, mainGroup}`（只取需要的字段）。"""
    objects: dict[str, dict] = {}
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        match = OBJECT_START_RE.match(lines[index])
        if not match:
            index += 1
            continue
        oid, rest = match.group(1), match.group(2)
        if rest.endswith("};"):
            body = rest[:-2]
            index += 1
        else:
            body_lines = [rest]
            index += 1
            while index < len(lines) and lines[index] != "\t\t};":
                body_lines.append(lines[index])
                index += 1
            index += 1  # 跳过 `\t\t};`
            body = "\n".join(body_lines)
        _put(objects, oid, body)
    return objects


def _put(objects: dict[str, dict], oid: str, body: str) -> None:
    if oid in objects:
        return
    item: dict = {}
    if isa := ISA_RE.search(body):
        item["isa"] = isa.group(1)
    if path := PATH_RE.search(body):
        item["path"] = (path.group(1) if path.group(1) is not None else path.group(2)).strip()
    if tree := TREE_RE.search(body):
        item["sourceTree"] = (tree.group(1) if tree.group(1) is not None else tree.group(2)).strip()
    if children := CHILDREN_RE.search(body):
        item["children"] = ID_RE.findall(children.group(1))
    if main_group := MAIN_GROUP_RE.search(body):
        item["mainGroup"] = main_group.group(1)
    if item:
        objects[oid] = item


def _display(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def walk_project(objects: dict[str, dict]) -> tuple[set[Path], list[str]]:
    """解析整棵引用树：返回（已登记的磁盘路径, 悬空引用说明）。"""
    project = next((o for o in objects.values() if o.get("isa") == "PBXProject"), None)
    if project is None or "mainGroup" not in project:
        return set(), []  # 解析不了就不误报，交给 Xcode 自己说

    registered: set[Path] = set()
    problems: list[str] = []

    def resolve(oid: str, parent: Path, seen: set[str]) -> None:
        if oid in seen:
            return
        seen.add(oid)
        item = objects.get(oid)
        if item is None:
            problems.append(f"{oid}: 对象不存在（悬空引用）")
            return
        isa = item.get("isa", "")
        path = item.get("path")
        tree = item.get("sourceTree", "<group>")

        if tree in SKIP_SOURCE_TREES:
            return
        if tree == "<absolute>":
            full = Path(path) if path else parent
        else:
            base = ROOT if tree == "SOURCE_ROOT" else parent
            full = (base / path) if path else base

        if isa == "PBXFileReference":
            registered.add(full.resolve())
        if isa in {"PBXGroup", "PBXFileReference", "PBXVariantGroup", "XCVersionGroup"} and path:
            if not full.exists():
                problems.append(f"{isa} “{path}” → {_display(full)}（磁盘上不存在）")

        for child in item.get("children", []):
            resolve(child, full, seen)

    roots = project["mainGroup"]
    for oid in (roots if isinstance(roots, list) else [roots]):
        resolve(oid, ROOT, set())
    return registered, problems


def main() -> int:
    if not PROJECT.exists():
        print(f"[pbxproj] 找不到工程文件: {PROJECT}")
        return 2

    text = PROJECT.read_text(encoding="utf-8")
    objects = parse_objects(text)
    registered, dangling = walk_project(objects)

    # 对象 ID 必须是 24 位十六进制。Xcode 对其它长度有时"能读"，但保存时会重写整个工程，
    # 表现为莫名其妙的大 diff（2026-11-09 手工加文件时写出过 25 位的 ID）。
    malformed_ids = [
        line.strip()
        for line in text.splitlines()
        if (match := MALFORMED_ID_RE.match(line)) and len(match.group(1)) != 24
    ]

    missing: list[Path] = []
    for base in SOURCE_DIRS:
        for path in sorted(base.rglob("*.swift")):
            if path.resolve() not in registered:
                missing.append(path.relative_to(ROOT))

    if missing:
        print("[pbxproj] 以下文件没有登记进 OrzMC.xcodeproj（干净构建会失败）：")
        for path in missing:
            print(f"  - {path}")
        print(
            "\n登记方法：在 Xcode 里把文件拖进对应分组（或手工加 PBXBuildFile /"
            " PBXFileReference / group children / Sources phase 四项）。"
        )

    if dangling:
        print("[pbxproj] 以下引用在磁盘上不存在（Xcode 项目导航器里会显示成红色）：")
        for item in dangling:
            print(f"  - {item}")
        print(
            "\n处理：删掉这些 PBXFileReference / PBXGroup（连同 children 里的条目），"
            "或在 Xcode 里移除引用。"
        )

    if malformed_ids:
        print("[pbxproj] 以下对象 ID 不是 24 位十六进制（Xcode 保存时会重写工程）：")
        for item in malformed_ids:
            print(f"  - {item}")

    if missing or dangling or malformed_ids:
        return 1

    print("[pbxproj] 应用源文件全部已登记，且没有悬空引用（OrzMC.xcodeproj）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
