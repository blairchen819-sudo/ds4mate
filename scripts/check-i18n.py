#!/usr/bin/env python3
"""校验界面词条表与代码用键是否一致。

用法：./scripts/check-i18n.py
退出码：0 = 一致；1 = 有问题（build.sh 会因此中断）

检查项：
1. 代码里用到的 key 必须在 en / zh 两张表里都有；
2. 两张表的 key 集合完全一致（否则切语言会退化成显示另一种语言）；
3. 没有空词条；
4. 同一个 key 的中英占位符（%@ / %ld）数量与顺序一致；
5. 提示表里没被引用到的 key（不算错误，catalog.* 是间接引用，见下）。

间接引用：ShortcutCatalog 的 `titleKey:` 与 HIDControllerService 的 `setStatus(`
都会走本地化，正则里一并计入。
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLE = ROOT / "Sources/DS4Mate/App/LocalizableStrings.swift"
SOURCES = ROOT / "Sources"

ENTRY_RE = re.compile(r'^\s*"([^"]+)":\s*"((?:[^"\\]|\\.)*)",\s*$', re.M)
# 直接调用：L("x") / i18n.t("x") / t("x", in:)
CALL_RE = re.compile(r'(?:\bL|\.t)\(\s*"([A-Za-z0-9._]+)"')
# 间接调用：`titleKey: "x"`（ShortcutCatalog）/ `setStatus("x", ...)`（HID 层）
INDIRECT_RE = re.compile(
    r'titleKey:\s*"([A-Za-z0-9._]+)"'
    r'|setStatus\(\s*"([A-Za-z0-9._]+)"'
    r'|statusKey: String = "([A-Za-z0-9._]+)"'
)
PLACEHOLDER_RE = re.compile(r'%[-0-9.]*[@a-zA-Z]')


def load_tables():
    src = TABLE.read_text(encoding="utf-8")
    en_at = src.index("static let en: [String: String] = [")
    zh_at = src.index("static let zh: [String: String] = [")
    return dict(ENTRY_RE.findall(src[en_at:zh_at])), dict(ENTRY_RE.findall(src[zh_at:]))


def used_keys():
    keys = set()
    for path in SOURCES.rglob("*.swift"):
        if path.name == "LocalizableStrings.swift":
            continue
        text = path.read_text(encoding="utf-8")
        keys |= set(CALL_RE.findall(text))
        for groups in INDIRECT_RE.findall(text):
            keys |= {g for g in groups if g}
    return keys


def main():
    en, zh = load_tables()
    used = used_keys()

    problems = []

    for title, missing in (
        ("代码用到、英文表缺失", sorted(used - set(en))),
        ("代码用到、中文表缺失", sorted(used - set(zh))),
        ("只在英文表里", sorted(set(en) - set(zh))),
        ("只在中文表里", sorted(set(zh) - set(en))),
    ):
        if missing:
            problems.append((title, missing))

    empty = sorted([k for k, v in en.items() if not v.strip()] + [k for k, v in zh.items() if not v.strip()])
    if empty:
        problems.append(("空词条", empty))

    mismatched = sorted(
        k for k in set(en) & set(zh)
        if PLACEHOLDER_RE.findall(en[k]) != PLACEHOLDER_RE.findall(zh[k])
    )
    if mismatched:
        problems.append(("中英占位符不一致", mismatched))

    unused = sorted(set(en) - used)

    print(f"词条：en={len(en)} zh={len(zh)}；代码引用={len(used)}")
    if unused:
        print(f"提示：{len(unused)} 条词条当前未被引用（可能是预留）")

    if not problems:
        print("✓ 词条一致")
        return 0

    for title, items in problems:
        print(f"\n✗ {title}（{len(items)}）")
        for item in items[:20]:
            print(f"    {item}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
