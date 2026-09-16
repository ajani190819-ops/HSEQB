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

    # --- duplicate member names in the same class (CS0102) -------------
    # A field and a method that share a name is legal in most languages
    # and illegal in C#. This is what broke the v16 engine.
    def cls_name(n):
        nm = n.child_by_field_name('name')
        return src[nm.start_byte:nm.end_byte].decode() if nm else '?'

    for cls in collect(tree.root_node, {'class_declaration','struct_declaration'}):
        seen = {}
        body = cls.child_by_field_name('body')
        if body is None: continue
        for member in body.children:
            names = []
            if member.type == 'field_declaration':
                vd = next((c for c in member.children if c.type == 'variable_declaration'), None)
                if vd:
                    for dcl in vd.children:
                        if dcl.type == 'variable_declarator':
                            names.append(('field', src[dcl.children[0].start_byte:dcl.children[0].end_byte].decode()))
            elif member.type == 'method_declaration':
                nm = member.child_by_field_name('name')
                if nm: names.append(('method', src[nm.start_byte:nm.end_byte].decode()))
            elif member.type == 'property_declaration':
                nm = member.child_by_field_name('name')
                if nm: names.append(('property', src[nm.start_byte:nm.end_byte].decode()))
            for kind, nm in names:
                seen.setdefault(nm, []).append((kind, line_of(src, member.start_byte)))
        for nm, uses in seen.items():
            kinds = set(k for k, _ in uses)
            # overloaded methods are fine; a name used as two DIFFERENT
            # kinds of member is not
            if len(uses) > 1 and len(kinds) > 1:
                where = ', '.join('%s@%d' % (k, l) for k, l in uses)
                problems.append((uses[0][1], 'CS0102',
                                 "class %s defines '%s' twice (%s)" % (cls_name(cls), nm, where)))

    # --- calls to same-class methods with the wrong argument count ------
    classes = {}
    def txt(n): return src[n.start_byte:n.end_byte].decode()
    def gather(n, cls=None):
        if n.type == 'class_declaration':
            cls = txt(n.child_by_field_name('name'))
            classes.setdefault(cls, {'members': set(), 'methods': {}})
        if cls:
            if n.type == 'field_declaration':
                vd = next((c for c in n.children if c.type == 'variable_declaration'), None)
                if vd:
                    for dcl in vd.children:
                        if dcl.type == 'variable_declarator':
                            classes[cls]['members'].add(txt(dcl.children[0]))
            elif n.type == 'property_declaration':
                classes[cls]['members'].add(txt(n.child_by_field_name('name')))
            elif n.type == 'method_declaration':
                nm = txt(n.child_by_field_name('name'))
                pl = n.child_by_field_name('parameters')
                ar = len([c for c in pl.children if c.type == 'parameter']) if pl else 0
                classes[cls]['members'].add(nm)
                classes[cls]['methods'].setdefault(nm, set()).add(ar)
        for c in n.children: gather(c, cls)
    gather(tree.root_node)

    def arity(n, cls=None):
        if n.type == 'class_declaration': cls = txt(n.child_by_field_name('name'))
        if cls and n.type == 'invocation_expression':
            fn = n.children[0]
            if fn.type == 'identifier' and txt(fn) in classes.get(cls, {}).get('methods', {}):
                al = n.child_by_field_name('arguments')
                na = len([c for c in al.children if c.type == 'argument']) if al else 0
                decl = classes[cls]['methods'][txt(fn)]
                if na not in decl:
                    problems.append((line_of(src, n.start_byte), 'CS1501',
                                     "%s(...) called with %d args, declared %s"
                                     % (txt(fn), na, sorted(decl))))
        for c in n.children: arity(c, cls)
    arity(tree.root_node)

    # --- gr./gz. accesses that Zone does not declare --------------------
    if 'Zone' in classes:
        zm = classes['Zone']['members']
        def zchk(n):
            if n.type == 'member_access_expression':
                o = n.child_by_field_name('expression')
                fl = n.child_by_field_name('name')
                if (o is not None and fl is not None and o.type == 'identifier'
                        and txt(o) in ('gr', 'gz') and txt(fl) not in zm):
                    problems.append((line_of(src, n.start_byte), 'CS1061',
                                     "Zone has no member '%s'" % txt(fl)))
            for c in n.children: zchk(c)
        zchk(tree.root_node)

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
