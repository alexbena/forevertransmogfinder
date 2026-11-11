# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Gitano Calvo
"""Pure-Python reader for Lua table literals, as used by the QuestieDB data files.

Handles `QuestieDB.xxxData = [[return { ... }]]` and the correction modules whose `Load()` returns a table
keyed by symbols such as `[npcKeys.minLevel]` or `zoneIDs.WETLANDS`. Only data is evaluated: table
constructors, strings, numbers, true/false/nil and dotted names (passed to a resolver callback). Code is
never executed; an expression that cannot be read comes back as an `Unparsed` marker.
"""
import re

__all__ = ['parse_value', 'parse_long_string_table', 'parse_return_table', 'Unparsed', 'to_list']


class Unparsed(str):
    """Marker for an expression that was skipped (code, not data)."""


_TOKEN = re.compile(r'''
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<leq>=*)\[)
  | (?P<comment>--[^\n]*)
  | (?P<lstr>\[(?P<seq>=*)\[)
  | (?P<str>"(?:[^"\\\n]|\\.|\\\n)*"|'(?:[^'\\\n]|\\.|\\\n)*')
  | (?P<num>0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|[{}\[\]=,;().:+\-*/%^#<>])
''', re.S | re.X)

_ESC = re.compile(r'\\(\d{1,3}|x[0-9a-fA-F]{2}|\n|.)', re.S)
_ESCMAP = {'n': '\n', 't': '\t', 'r': '\r', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v',
           '\\': '\\', '"': '"', "'": "'", '\n': '\n'}


def _unescape(body):
    def rep(m):
        g = m.group(1)
        if g.isdigit():
            return chr(int(g))
        if g[0] == 'x' and len(g) == 3:
            return chr(int(g[1:], 16))
        return _ESCMAP.get(g, g)
    return _ESC.sub(rep, body)


class _Lexer:
    def __init__(self, text, pos=0):
        self.t = text
        self.p = pos
        self.peeked = None

    def _next(self):
        t = self.t
        while self.p < len(t):
            m = _TOKEN.match(t, self.p)
            if not m:
                raise ValueError('bad character %r at %d' % (t[self.p], self.p))
            kind = m.lastgroup
            if kind in ('leq', 'seq'):
                kind = 'lcomment' if m.group('lcomment') else 'lstr'
            if kind == 'ws' or kind == 'comment':
                self.p = m.end()
                continue
            if m.group('lcomment') is not None:
                close = ']' + m.group('leq') + ']'
                e = t.find(close, m.end())
                self.p = (e + len(close)) if e >= 0 else len(t)
                continue
            if m.group('lstr') is not None:
                close = ']' + m.group('seq') + ']'
                e = t.find(close, m.end())
                body = t[m.end():e]
                if body.startswith('\n'):
                    body = body[1:]
                self.p = e + len(close)
                return ('str', body, m.start())
            self.p = m.end()
            if m.group('str') is not None:
                return ('str', _unescape(m.group('str')[1:-1]), m.start())
            if m.group('num') is not None:
                s = m.group('num')
                if s[:2].lower() == '0x':
                    return ('num', int(s, 16), m.start())
                if re.fullmatch(r'\d+', s):
                    return ('num', int(s), m.start())
                return ('num', float(s), m.start())
            if m.group('name') is not None:
                return ('name', m.group('name'), m.start())
            return ('op', m.group('op'), m.start())
        return ('eof', None, self.p)

    def peek(self):
        if self.peeked is None:
            self.peeked = self._next()
        return self.peeked

    def next(self):
        tok = self.peek()
        self.peeked = None
        return tok


def _default_resolver(path):
    return Unparsed(path)


class _Parser:
    def __init__(self, text, pos=0, resolver=None):
        self.lx = _Lexer(text, pos)
        self.resolve = resolver or _default_resolver

    def expect(self, val):
        k, v, p = self.lx.next()
        if v != val:
            raise ValueError('expected %r, got %r at %d' % (val, v, p))

    def value(self):
        k, v, p = self.lx.next()
        if k == 'op' and v == '{':
            return self.table()
        if k == 'op' and v == '-':
            nk, nv, _ = self.lx.next()
            if nk == 'num':
                return self._tail(-nv)
            if nk == 'name':
                path = nv
                while self.lx.peek()[1] == '.' and self.lx.peek()[0] == 'op':
                    self.lx.next()
                    path += '.' + str(self.lx.next()[1])
                v = self.resolve(path)
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    return self._tail(-v)
                return self._tail(Unparsed('-' + path))
            return self._skip_expr(Unparsed('-' + str(nv)))
        if k == 'str':
            return self._tail(v)
        if k == 'num':
            return self._tail(v)
        if k == 'name':
            if v == 'true':
                return True
            if v == 'false':
                return False
            if v == 'nil':
                return None
            if v == 'function':
                return self._skip_function()
            path = v
            while self.lx.peek()[1] == '.' and self.lx.peek()[0] == 'op':
                self.lx.next()
                path += '.' + str(self.lx.next()[1])
            nk, nv, _ = self.lx.peek()
            if nk == 'op' and nv in ('(', ':', '['):
                return self._skip_expr(Unparsed(path))
            return self._tail(self.resolve(path))
        if k == 'op' and v == '(':
            inner = self.value()
            self.expect(')')
            return self._tail(inner)
        raise ValueError('unexpected %r at %d' % (v, p))

    def _tail(self, val):
        """Binary operators after a value: simple numeric + - * / and '..' are evaluated."""
        k, v, _ = self.lx.peek()
        if k == 'op' and v in ('+', '-', '*', '/', '..', '%', '^'):
            self.lx.next()
            rhs = self.value()
            try:
                if v == '+':
                    return val + rhs
                if v == '-':
                    return val - rhs
                if v == '*':
                    return val * rhs
                if v == '/':
                    return val / rhs
                if v == '..':
                    return str(val) + str(rhs)
            except TypeError:
                return Unparsed('expr')
            return Unparsed('expr')
        return val

    def _skip_expr(self, marker):
        depth = 0
        while True:
            k, v, _ = self.lx.peek()
            if k == 'eof':
                return marker
            if k == 'op' and v in ('(', '{', '['):
                depth += 1
            elif k == 'op' and v in (')', '}', ']'):
                if depth == 0:
                    return marker
                depth -= 1
            elif k == 'op' and v in (',', ';') and depth == 0:
                return marker
            self.lx.next()

    def _skip_function(self):
        depth = 1
        while depth:
            k, v, _ = self.lx.next()
            if k == 'eof':
                break
            if k == 'name' and v in ('function', 'do', 'if'):
                depth += 1
            elif k == 'name' and v == 'end':
                depth -= 1
        return Unparsed('function')

    def table(self):
        arr, hsh = [], {}
        while True:
            k, v, p = self.lx.peek()
            if k == 'op' and v == '}':
                self.lx.next()
                break
            if k == 'op' and v in (',', ';'):
                self.lx.next()
                continue
            if k == 'op' and v == '[':
                self.lx.next()
                key = self.value()
                self.expect(']')
                self.expect('=')
                hsh[key] = self.value()
                continue
            if k == 'name':
                save_p, save_peek = self.lx.p, self.lx.peeked
                self.lx.next()
                k2, v2, _ = self.lx.peek()
                if k2 == 'op' and v2 == '=':
                    self.lx.next()
                    hsh[v] = self.value()
                    continue
                self.lx.p, self.lx.peeked = save_p, save_peek
            arr.append(self.value())
        if not hsh:
            return arr
        if not arr:
            return hsh
        out = {i + 1: x for i, x in enumerate(arr)}
        out.update(hsh)
        return out


def parse_value(text, pos=0, resolver=None):
    """Parse one Lua value starting at text[pos]."""
    return _Parser(text, pos, resolver).value()


def parse_long_string_table(text, var):
    """`var = [[return { ... }]]`: returns the table."""
    m = re.search(re.escape(var) + r'\s*=\s*\[(=*)\[', text)
    if not m:
        raise KeyError(var)
    close = ']' + m.group(1) + ']'
    end = text.find(close, m.end())
    body = text[m.end():end]
    r = re.match(r'\s*return\s*', body)
    return parse_value(body, r.end() if r else 0)


def parse_return_table(text, resolver=None, after=None):
    """Parse the table after the first `return {` (after the marker `after` when given)."""
    start = text.find(after) if after else 0
    m = re.compile(r'\breturn\s*\{').search(text, max(start, 0))
    if not m:
        return {}
    return parse_value(text, m.end() - 1, resolver)


def to_list(v):
    """Lua sequence (list, or dict with int keys) -> Python list with None holes."""
    if v is None:
        return []
    if isinstance(v, list):
        return v
    if isinstance(v, dict):
        ints = [k for k in v if isinstance(k, int)]
        if not ints:
            return []
        return [v.get(i) for i in range(1, max(ints) + 1)]
    return [v]
