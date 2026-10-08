"""在沒有 Swift 編譯器的環境下，粗略檢查每個 Swift 檔案的括號是否成對。

用法：python scripts/lint_brackets.py [根目錄]
"""
import os
import re
import sys


def strip(source: str) -> str:
    source = re.sub(r'"""[\s\S]*?"""', '""', source)
    source = re.sub(r'/\*[\s\S]*?\*/', '', source)
    source = re.sub(r'//.*', '', source)
    source = re.sub(r'#?"(?:\\.|[^"\\\n])*"#?', '""', source)
    return source


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    failed = 0
    for dirpath, _, files in os.walk(root):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as f:
                text = strip(f.read())
            stack = []
            pairs = {")": "(", "]": "[", "}": "{"}
            error = None
            for line_no, line in enumerate(text.splitlines(), 1):
                for ch in line:
                    if ch in "([{":
                        stack.append((ch, line_no))
                    elif ch in ")]}":
                        if not stack or stack[-1][0] != pairs[ch]:
                            error = f"line {line_no}: unexpected '{ch}'"
                            break
                        stack.pop()
                if error:
                    break
            if not error and stack:
                error = f"unclosed '{stack[-1][0]}' from line {stack[-1][1]}"
            rel = os.path.relpath(path, root)
            if error:
                failed += 1
                print(f"FAIL {rel}: {error}")
            else:
                print(f"ok   {rel}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
