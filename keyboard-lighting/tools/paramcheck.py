#!/usr/bin/env python3
"""Cross-script parameter check.

Catches the class of bug where one script invokes another with a value the
target's param() block would reject at bind time - before any of its code
runs. That is how -Effect zonetest shipped broken: the mode existed, but
the ValidateSet did not list it.
"""
import re, sys, pathlib

HERE = pathlib.Path(__file__).resolve().parent.parent

def param_block(text):
    i = text.index('param(')
    depth = 0
    for j in range(i + 5, len(text)):
        if text[j] == '(':
            depth += 1
        elif text[j] == ')':
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
    raise ValueError('unterminated param block')

def declared(block):
    """name -> {'set': [...] or None, 'range': (lo,hi) or None}"""
    out = {}
    # split on parameter declarations, keeping the attributes before each
    parts = re.split(r'(\[(?:switch|string|double|int|bool)\]\$\w+)', block)
    pending = ''
    for chunk in parts:
        m = re.match(r'\[(?:switch|string|double|int|bool)\]\$(\w+)', chunk)
        if not m:
            pending = chunk
            continue
        name = m.group(1)
        vs = re.search(r'ValidateSet\(([^)]*)\)', pending, re.S)
        vr = re.search(r'ValidateRange\(\s*([\d.]+)\s*,\s*([\d.]+)\s*\)', pending)
        out[name] = {
            'set': re.findall(r"'([^']*)'", vs.group(1)) if vs else None,
            'range': (float(vr.group(1)), float(vr.group(2))) if vr else None,
        }
    return out

def invocations(text):
    """(param, literal) pairs passed as '-Name', 'value' in an argument array."""
    found = []
    for m in re.finditer(r"'-(\w+)'\s*,\s*'([^']*)'", text):
        found.append((m.group(1), m.group(2)))
    return found

def main():
    engine = (HERE / 'Aura-Background.ps1').read_text(encoding='utf-8')
    decl = declared(param_block(engine))

    problems = []
    for caller in ['Zones.ps1', 'Tray.ps1', 'Setup.ps1']:
        p = HERE / caller
        if not p.exists():
            continue
        text = p.read_text(encoding='utf-8')
        for name, val in invocations(text):
            if name in ('NoProfile', 'ExecutionPolicy', 'File', 'Command',
                        'WindowStyle', 'Verb', 'FilePath', 'ArgumentList'):
                continue
            if name not in decl:
                problems.append(f'{caller}: -{name} is not a parameter of Aura-Background.ps1')
                continue
            spec = decl[name]
            if spec['set'] is not None and val not in spec['set']:
                problems.append(
                    f'{caller}: -{name} {val!r} rejected by ValidateSet '
                    f'(allowed: {", ".join(spec["set"][:6])}...)')
            if spec['range'] is not None:
                try:
                    f = float(val)
                    lo, hi = spec['range']
                    if not (lo <= f <= hi):
                        problems.append(f'{caller}: -{name} {val} outside {lo}..{hi}')
                except ValueError:
                    pass

    # every effect the engine implements should be selectable
    cases = set(re.findall(r'case "(\w+)":', engine))
    allowed = set(decl.get('Effect', {}).get('set') or [])
    for c in sorted(cases - allowed - {'default'}):
        problems.append(f'effect "{c}" is implemented but missing from -Effect ValidateSet')

    for pr in problems:
        print('  ' + pr)
    print(f'\nPARAM PROBLEMS: {len(problems)}')
    return 1 if problems else 0

if __name__ == '__main__':
    sys.exit(main())
