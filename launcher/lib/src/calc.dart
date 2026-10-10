/// A small arithmetic evaluator so the launcher can answer "12*7" and
/// "2^10/3" as you type.
library;

import 'dart:math' as math;

/// Evaluates [input] when it looks like arithmetic: numbers, `+ - * / % ^`,
/// parentheses and a few functions (sqrt, sin, cos, tan, ln, log, abs) and
/// constants (pi, e). Returns null for anything else, including plain
/// numbers, which aren't worth answering.
double? evaluate(String input) {
  final s = input.trim().replaceAll('×', '*').replaceAll('÷', '/').replaceAll(',', '.');
  if (s.isEmpty || !RegExp(r'[0-9]').hasMatch(s)) return null;
  if (!RegExp(r'[-+*/%^()a-z]').hasMatch(s.toLowerCase())) return null;
  try {
    final parser = _Parser(s.toLowerCase());
    final v = parser.expression();
    parser.skipSpace();
    if (!parser.atEnd) return null;
    return v.isNaN ? null : v;
  } on FormatException {
    return null;
  }
}

/// Formats a result without float noise: integers plainly, others to at
/// most 10 significant decimals.
String formatNumber(double v) {
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  var s = v.toStringAsPrecision(12);
  if (s.contains('e')) return s;
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}

class _Parser {
  final String s;
  int i = 0;
  _Parser(this.s);

  bool get atEnd => i >= s.length;

  void skipSpace() {
    while (!atEnd && s[i] == ' ') {
      i++;
    }
  }

  bool eat(String ch) {
    skipSpace();
    if (!atEnd && s[i] == ch) {
      i++;
      return true;
    }
    return false;
  }

  double expression() {
    var v = term();
    while (true) {
      if (eat('+')) {
        v += term();
      } else if (eat('-')) {
        v -= term();
      } else {
        return v;
      }
    }
  }

  double term() {
    var v = unary();
    while (true) {
      if (eat('*')) {
        v *= unary();
      } else if (eat('/')) {
        v /= unary();
      } else if (eat('%')) {
        v %= unary();
      } else {
        return v;
      }
    }
  }

  double unary() {
    if (eat('-')) return -unary();
    if (eat('+')) return unary();
    return power();
  }

  double power() {
    final base = atom();
    if (eat('^')) return math.pow(base, unary()).toDouble();
    return base;
  }

  static final _functions = <String, double Function(double)>{
    'sqrt': math.sqrt,
    'sin': math.sin,
    'cos': math.cos,
    'tan': math.tan,
    'ln': math.log,
    'log': (x) => math.log(x) / math.ln10,
    'abs': (x) => x.abs(),
  };

  double atom() {
    skipSpace();
    if (eat('(')) {
      final v = expression();
      if (!eat(')')) throw const FormatException('missing )');
      return v;
    }
    final start = i;
    while (!atEnd && RegExp(r'[0-9.]').hasMatch(s[i])) {
      i++;
    }
    if (i > start) {
      final v = double.tryParse(s.substring(start, i));
      if (v == null) throw const FormatException('bad number');
      return v;
    }
    while (!atEnd && RegExp(r'[a-z]').hasMatch(s[i])) {
      i++;
    }
    final word = s.substring(start, i);
    if (word == 'pi') return math.pi;
    if (word == 'e') return math.e;
    final f = _functions[word];
    if (f != null) {
      if (!eat('(')) throw const FormatException('expected (');
      final v = expression();
      if (!eat(')')) throw const FormatException('missing )');
      return f(v);
    }
    throw const FormatException('unexpected input');
  }
}
