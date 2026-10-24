#!/usr/bin/env python3
"""Lists English UI strings in the app that a translation doesn't cover.

  tools/check-localization.py ru

Run from the repository root. Interpolations become %lld (counts) or %@
(text), the way SwiftUI and String(localized:) build their keys. Exits 1 when
something is missing, so it can run in CI.
"""
import glob, plistlib, re, sys

lang = sys.argv[1] if len(sys.argv) > 1 else "ru"
folder = f"Localization/{lang}.lproj"

def strings_keys(path):
    text = open(path, encoding="utf-8").read()
    keys = set()
    for m in re.finditer(r'^\s*"((?:[^"\\]|\\.)*)"\s*=', text, re.M):
        keys.add(re.sub(r'\\(.)', lambda e: {"n": "\n", "t": "\t"}.get(e.group(1), e.group(1)), m.group(1)))
    return keys

keys = strings_keys(f"{folder}/Localizable.strings")
try:
    keys |= set(plistlib.load(open(f"{folder}/Localizable.stringsdict", "rb")))
except FileNotFoundError:
    pass

COUNT = re.compile(r"count|protected|\.on\b|\.total|since|Count\b|number|welcomePage")

def literals(code):
    """Yields (offset, text) for each one-line string literal."""
    i, n = 0, len(code)
    while i < n:
        if code.startswith("//", i):
            i = code.find("\n", i)
            i = n if i < 0 else i
            continue
        if code[i] == '"' and not code.startswith('"""', i):
            start, j, out = i, i + 1, ""
            while j < n and code[j] != '"':
                if code.startswith("\\(", j):
                    depth, k = 1, j + 2
                    while depth:
                        if code[k] == "(": depth += 1
                        elif code[k] == ")": depth -= 1
                        elif code[k] == '"': k = code.find('"', k + 1)
                        k += 1
                    out += "%lld" if COUNT.search(code[j + 2:k - 1]) else "%@"
                    j = k
                    continue
                if code[j] == "\\":
                    out += {"n": "\n", "t": "\t"}.get(code[j + 1], code[j + 1])
                    j += 2
                    continue
                out += code[j]
                j += 1
            yield start, out
            i = j + 1
            continue
        i += 1

# In the shared engine files only these fields reach the window.
DATA_FIELD = re.compile(r'(?:title|detail|caveat|prompt):\s*(?:String\(localized:\s*)?(?:[^"\n]*\?\s*)?$|case \.\w+: return $|isUpdater \? nil : $')
NOT_UI = re.compile(r'^((?:%lld|%@)+$|https?:|/|~|com\.|io\.|group\.|[a-z0-9.\-_:]+$|[A-Z_]+$|[a-z][A-Za-z]*$|[A-Z][a-z]*[A-Z]\w*$|• $|.*\.(app|plist)$)')
ENGINE = ["Tweaks.swift", "Catalog.swift", "Storage.swift", "BackgroundItems.swift"]
# Words people know by their English name, used alone.
NAMES = {"Finder", "Genmoji", "Image Playground", "Wi-Fi", "Bluetooth", "RemoveMacAI", "Apple Intelligence"}

missing = []
files = sorted(glob.glob("Sources/removemacai/App/*.swift")) + [f"Sources/removemacai/{f}" for f in ENGINE]
for path in files:
    if path.endswith(("Snapshots.swift", "L10n.swift", "AppLanguage.swift")):
        continue
    code = open(path, encoding="utf-8").read()
    engine = path.split("/")[-1] in ENGINE
    for start, text in literals(code):
        line_start = code.rfind("\n", 0, start) + 1
        before = code[line_start:start]
        if engine and not DATA_FIELD.search(before.strip() + " " if before.strip().endswith(("?", ":", "return")) else before):
            continue
        if engine and text[:1].islower() and not text.startswith(("macOS", "iPhone", "iPad")):
            continue
        if text in keys or text in NAMES or NOT_UI.match(text) or not re.search(r"[A-Za-z]{2}", text):
            continue
        if not engine and re.search(r"(systemImage|systemName|forKey|environment\[|id:|named:)\s*:?\s*$", before):
            continue
        missing.append(f"{path}:{code.count(chr(10), 0, start) + 1}: {text!r}")

for m in missing:
    print(m)
print(f"{lang}: {len(keys)} entries, {len(missing)} strings without a translation")
sys.exit(1 if missing else 0)
