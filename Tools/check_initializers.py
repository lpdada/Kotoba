#!/usr/bin/env python3
"""Approximate check: do call sites pass labels that match struct properties?

Parses stored properties of every struct we declare, then inspects `Type(` call
sites for label names, order, and obviously missing required arguments.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "Kotoba")

def strip_noise(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            if src.startswith('"""', i):
                j = src.find('"""', i + 3); i = (j + 3) if j != -1 else n
            else:
                i += 1
                while i < n:
                    if src[i] == '\\': i += 2; continue
                    if src[i] == '"': i += 1; break
                    i += 1
            out.append('""')
            continue
        if src.startswith('//', i):
            j = src.find('\n', i); i = n if j == -1 else j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i); i = n if j == -1 else j + 2; continue
        out.append(c); i += 1
    return ''.join(out)

def match_brace(text, open_idx):
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == '{': depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0: return i
    return len(text) - 1

def match_paren(text, open_idx):
    depth = 0
    for i in range(open_idx, len(text)):
        if text[i] == '(': depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0: return i
    return len(text) - 1

structs = {}   # name -> list of (prop, has_default, is_optional)
STRUCTS_WITH_INIT = set()
sources = {}
for base, _d, files in os.walk(APP):
    for name in sorted(files):
        if not name.endswith('.swift'): continue
        path = os.path.join(base, name)
        raw = open(path, encoding='utf-8').read()
        clean = strip_noise(raw)
        sources[os.path.relpath(path, ROOT)] = (raw, clean)
        for m in re.finditer(r'\bstruct\s+(\w+)[^\{]*\{', clean):
            name_ = m.group(1)
            start = clean.index('{', m.end() - 1)
            end = match_brace(clean, start)
            body = clean[start + 1:end]
            props = []
            has_custom_init = bool(re.search(r'\binit\s*\(', body))
            depth = 0
            for line in body.split('\n'):
                stripped = re.sub(r'^@\w+(\([^)]*\))?\s*', '', line.strip())
                if depth == 0:
                    pm = re.match(r'(?:var|let)\s+(\w+)\s*(?::\s*([^={]+?))?\s*(=|$)', stripped)
                    if pm and 'static' not in stripped and 'func ' not in stripped:
                        prop = pm.group(1)
                        rest = stripped[pm.end():]
                        has_default = '=' in stripped
                        is_optional = bool(pm.group(2) and pm.group(2).strip().endswith('?'))
                        is_computed = '{' in rest
                        if not is_computed:
                            props.append((prop, has_default, is_optional))
                depth += line.count('{') - line.count('}')
            structs[name_] = props
            if re.search(r'\binit\s*\(', body):
                STRUCTS_WITH_INIT.add(name_)

problems = []
for rel, (raw, clean) in sources.items():
    for m in re.finditer(r'\b([A-Z]\w+)\s*\(', clean):
        name = m.group(1)
        if name not in structs: continue
        # skip the declaration itself / function decls
        prefix = clean[max(0, m.start() - 20):m.start()]
        if re.search(r'(struct|class|enum|func)\s*$', prefix.strip()): continue
        if re.search(r'(init|func)\s*$', prefix.strip()): continue
        open_idx = m.end() - 1
        close_idx = match_paren(clean, open_idx)
        args = clean[open_idx + 1:close_idx]
        # collect labels at depth 0
        labels, depth = [], 0
        token = ''
        for ch in args:
            if ch in '([{': depth += 1
            elif ch in ')]}': depth -= 1
            if depth == 0 and ch == ',':
                labels.append(token.strip()); token = ''
            elif depth == 0:
                token += ch
        if token.strip(): labels.append(token.strip())
        used = []
        for label in labels:
            lm = re.match(r'([A-Za-z_]\w*)\s*:', label)
            if lm: used.append(lm.group(1))
        props = structs[name]
        names = [p[0] for p in props]
        last_index = -1
        for label in used:
            if label not in names:
                problems.append(f"{rel}: {name}(...) uses unknown label '{label}' (props: {names})")
                continue
            idx = names.index(label)
            if idx < last_index:
                problems.append(f"{rel}: {name}(...) label '{label}' out of order")
            last_index = max(last_index, idx)
        if name in STRUCTS_WITH_INIT:
            continue
        required = [p[0] for p in props if not p[1] and not p[2]]
        missing = [p for p in required if p not in used]
        if missing:
            problems.append(f"{rel}: {name}(...) missing required {missing}")

seen = set()
for p in problems:
    if p in seen: continue
    seen.add(p)
    print(p)
print(f"\nchecked {len(structs)} structs, {len(sources)} files, {len(seen)} findings")
