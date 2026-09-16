#!/usr/bin/env python3
"""Parse the project's embedded C# with tree-sitter and report real errors.

Catches what regex scanning cannot: syntax errors anywhere in the file,
plus the specific C# rules that Add-Type enforces at runtime (CS0677
volatile-on-double being the one that killed v16).
"""
import re, sys, os
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
import tree_sitter_c_sharp as tscs
from tree_sitter import Language, Parser

LANG = Language(tscs.language())
parser = Parser(LANG)

VOLATILE_OK = {
    'sbyte','byte','short','ushort','int','uint','char','float','bool',
    'IntPtr','UIntPtr','object','string',
}

def collect(node, kinds, out=None):
    if out is None: out = []
    if node.type in kinds: out.append(node)
    for c in node.children: collect(c, kinds, out)
    return out

def line_of(src, byte):
    return src[:byte].count(b'\n') + 1

def check(name, code):
    problems = []
    src = code.encode('utf8')
    tree = parser.parse(src)

    # --- syntax errors -------------------------------------------------
    for n in collect(tree.root_node, {'ERROR'}):
        snippet = src[n.start_byte:n.start_byte+70].decode('utf8','replace').replace('\n',' ')
        problems.append((line_of(src, n.start_byte), 'SYNTAX ERROR', snippet))
    if tree.root_node.has_error and not problems:
        problems.append((0, 'SYNTAX ERROR', 'parser reported an error with no ERROR node'))
    for n in collect(tree.root_node, {'MISSING'}):
        problems.append((line_of(src, n.start_byte), 'MISSING TOKEN', n.type))

    # --- CS0677: volatile on an illegal type ---------------------------
    for fld in collect(tree.root_node, {'field_declaration'}):
        mods = [c for c in fld.children if c.type == 'modifier']
        if not any(src[m.start_byte:m.end_byte] == b'volatile' for m in mods):
            continue
        vd = next((c for c in fld.children if c.type == 'variable_declaration'), None)
        if vd is None: continue
        tnode = vd.children[0]
        ttext = src[tnode.start_byte:tnode.end_byte].decode()
        # arrays / pointers / generics are references -> legal
        if tnode.type in ('array_type','pointer_type','nullable_type','generic_name'):
            continue
        base = ttext.strip()
        if base in VOLATILE_OK:      continue
        if base and base[0].isupper():  # class / delegate / enum-ish
            continue
        problems.append((line_of(src, fld.start_byte), 'CS0677',
                         'volatile %s is not allowed' % base))

    # --- C#6+ syntax that Add-Type (C#5) rejects -----------------------
    for n in collect(tree.root_node, {'interpolated_string_expression'}):
        problems.append((line_of(src, n.start_byte), 'C#6', 'string interpolation'))
    for n in collect(tree.root_node, {'arrow_expression_clause'}):
        problems.append((line_of(src, n.start_byte), 'C#6', 'expression-bodied member'))
    for n in collect(tree.root_node, {'conditional_access_expression'}):
        problems.append((line_of(src, n.start_byte), 'C#6', 'null-conditional ?.'))
    for inv in collect(tree.root_node, {'invocation_expression'}):
        fn = inv.children[0]
        if src[fn.start_byte:fn.end_byte] == b'nameof':
            problems.append((line_of(src, inv.start_byte), 'C#6', 'nameof()'))
    # auto-property initialiser: { get; set; } = ...
    for p in collect(tree.root_node, {'property_declaration'}):
        if any(c.type == 'equals_value_clause' for c in p.children):
            problems.append((line_of(src, p.start_byte), 'C#6', 'auto-property initialiser'))

    # --- non-ASCII ------------------------------------------------------
    for i, ch in enumerate(code):
        if ord(ch) > 126:
            problems.append((code[:i].count('\n')+1, 'NON-ASCII', repr(ch)))
            break

    return problems

def main(paths):
    total = 0
    for label, code in paths:
        probs = check(label, code)
        status = 'OK' if not probs else 'FAIL (%d)' % len(probs)
        print('%-22s %s' % (label, status))
        for ln, kind, msg in sorted(probs)[:25]:
            print('    line %-6s %-14s %s' % (ln, kind, msg))
        total += len(probs)
    print()
    print('TOTAL PROBLEMS:', total)
    return 1 if total else 0

if __name__ == '__main__':
    eng = open(os.path.join(HERE,'Aura-Background.ps1'), encoding='utf-8').read()
    blocks = re.findall(r"@'\s*\n(.*?)\n'@", eng, re.S)
    items = [('engine block %d' % (i+1), b) for i, b in enumerate(blocks)]
    items.append(('ui_controls.cs.txt',
                  open(os.path.join(HERE,'ui_controls.cs.txt'), encoding='utf-8').read()))
    sys.exit(main(items))
