#!/usr/bin/env python3
"""Lightweight static checks for the Kotoba sources.

Not a Swift compiler: it verifies bracket balance, duplicate declarations, and
cross-references between the model hub (AppModel) and the views. Run it before
pushing so CI failures are about real compile errors, not typos.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "Kotoba")


def strip_noise(src: str) -> str:
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == '"':
            # multiline or single line string
            if src.startswith('"""', i):
                j = src.find('"""', i + 3)
                i = (j + 3) if j != -1 else n
            else:
                i += 1
                while i < n:
                    if src[i] == '\\':
                        i += 2
                        continue
                    if src[i] == '"':
                        i += 1
                        break
                    i += 1
            continue
        if c == '/' and src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j == -1 else j
            continue
        if c == '/' and src.startswith('/*', i):
            j = src.find('*/', i)
            i = n if j == -1 else j + 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def swift_files():
    for base, _dirs, files in os.walk(APP):
        for name in sorted(files):
            if name.endswith('.swift'):
                yield os.path.join(base, name)


def main() -> int:
    problems = []
    declarations = {}
    sources = {}

    for path in swift_files():
        rel = os.path.relpath(path, ROOT)
        src = open(path, encoding='utf-8').read()
        sources[rel] = src
        clean = strip_noise(src)
        for opening, closing, label in (('{', '}', 'braces'), ('(', ')', 'parens'), ('[', ']', 'brackets')):
            if clean.count(opening) != clean.count(closing):
                problems.append(f"{rel}: unbalanced {label} ({clean.count(opening)} vs {clean.count(closing)})")
        for match in re.finditer(r'^(?:public |private |internal |fileprivate )?(?:final )?(?:struct|class|enum|protocol|actor)\s+(\w+)', clean, re.M):
            name = match.group(1)
            declarations.setdefault(name, []).append(rel)

    for name, files in declarations.items():
        if len(files) > 1:
            problems.append(f"duplicate type declaration '{name}' in {files}")

    # AppModel surface
    app_src = sources.get(os.path.join('Kotoba', 'App', 'AppModel.swift'), '')
    members = set()
    for match in re.finditer(r'(?:func|var|let)\s+(\w+)', app_src):
        members.add(match.group(1))
    for match in re.finditer(r'lazy\s+var\s+(\w+)', app_src):
        members.add(match.group(1))

    # ReviewSessionModel surface
    session_src = sources.get(os.path.join('Kotoba', 'Services', 'ReviewSession.swift'), '')
    session_members = set(re.findall(r'(?:func|var|let)\s+(\w+)', session_src))
    session_members.add('init')

    known_app = members | {'init'}
    for rel, src in sources.items():
        if rel.endswith('AppModel.swift'):
            continue
        clean = strip_noise(src)
        for match in re.finditer(r'\bapp\.(\w+)', clean):
            name = match.group(1)
            if name in known_app:
                continue
            problems.append(f"{rel}: app.{name} is not declared on AppModel")
        if rel.endswith('ReviewView.swift'):
            for match in re.finditer(r'\bsession\.(\w+)', clean):
                name = match.group(1)
                if name in session_members:
                    continue
                problems.append(f"{rel}: session.{name} is not declared on ReviewSessionModel")

    if problems:
        print("FAILED")
        for problem in problems:
            print(" -", problem)
        return 1

    print(f"OK: {len(sources)} Swift files, {len(declarations)} types, no cross-reference problems")
    return 0


if __name__ == '__main__':
    sys.exit(main())
