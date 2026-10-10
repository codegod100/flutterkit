/// Fuzzy subsequence matching with scores that favour matches at word
/// starts and in runs, in the spirit of fzf.
library;

class FuzzyMatch {
  final double score;

  /// Indices into the text of the matched characters, ascending.
  final List<int> positions;

  const FuzzyMatch(this.score, this.positions);
}

const _matchScore = 16.0;
const _runBonus = 10.0;
const _boundaryBonus = 12.0;
const _firstCharBonus = 14.0;
const _gapPenalty = 1.0;
const _leadingPenalty = 0.6;
const _maxLeadingPenalty = 6.0;

bool _isSeparator(String ch) => ' -_./\\:()[]+,'.contains(ch);

bool _isBoundary(String text, int i) {
  if (i == 0) return true;
  final prev = text[i - 1];
  if (_isSeparator(prev)) return true;
  // camelCase: a capital after a lower-case letter.
  final ch = text[i];
  return ch != ch.toLowerCase() && prev == prev.toLowerCase() && prev != prev.toUpperCase();
}

/// Matches [pattern] against [text] case-insensitively, as a subsequence.
/// Spaces in [pattern] are ignored. Returns null when it doesn't match.
///
/// Every start of the first pattern character is tried and the best
/// scoring alignment kept, so "ff" in "Firefox" matches the F and the f of
/// "fox" rather than two letters of "Fir".
FuzzyMatch? fuzzyMatch(String pattern, String text) {
  final p = pattern.replaceAll(' ', '').toLowerCase();
  if (p.isEmpty) return const FuzzyMatch(0, []);
  final lower = text.toLowerCase();
  if (lower.length != text.length || p.length > lower.length) {
    // Case folding changed the length (rare scripts); fall back to plain
    // substring scoring.
    final i = lower.indexOf(p);
    if (i < 0) return null;
    return FuzzyMatch(p.length * _matchScore - i, [for (var k = 0; k < p.length; k++) i + k]);
  }

  FuzzyMatch? best;
  for (var start = lower.indexOf(p[0]); start >= 0; start = lower.indexOf(p[0], start + 1)) {
    final positions = _align(p, lower, text, start);
    if (positions == null) break; // later starts can't match either
    final score = _score(positions, text);
    if (best == null || score > best.score) best = FuzzyMatch(score, positions);
  }
  return best;
}

/// Greedy alignment from [start], preferring for each character a word
/// boundary or the very next character over the first plain occurrence.
List<int>? _align(String p, String lower, String text, int start) {
  final positions = [start];
  var i = start + 1;
  for (var k = 1; k < p.length; k++) {
    final ch = p[k];
    final first = lower.indexOf(ch, i);
    if (first < 0) return null;
    var pick = first;
    if (first != i) {
      // Look ahead for a boundary occurrence, as long as the rest of the
      // pattern still fits after it.
      for (var j = first; j >= 0 && j < lower.length; j = lower.indexOf(ch, j + 1)) {
        if (_isBoundary(text, j) && _fits(p, lower, k + 1, j + 1)) {
          pick = j;
          break;
        }
      }
    }
    positions.add(pick);
    i = pick + 1;
  }
  return positions;
}

bool _fits(String p, String lower, int k, int from) {
  var i = from;
  for (; k < p.length; k++) {
    i = lower.indexOf(p[k], i);
    if (i < 0) return false;
    i++;
  }
  return true;
}

double _score(List<int> positions, String text) {
  var score = 0.0;
  var run = 0;
  for (var k = 0; k < positions.length; k++) {
    final i = positions[k];
    score += _matchScore;
    if (_isBoundary(text, i)) score += _boundaryBonus;
    if (k > 0 && i == positions[k - 1] + 1) {
      run++;
      score += _runBonus * (run > 3 ? 3 : run) / 2;
    } else {
      run = 0;
      if (k > 0) score -= _gapPenalty * (i - positions[k - 1] - 1).clamp(0, 12);
    }
  }
  if (positions.first == 0) score += _firstCharBonus;
  score -= (positions.first * _leadingPenalty).clamp(0, _maxLeadingPenalty);
  // A pattern that covers the whole text is as good as it gets.
  if (positions.length == text.length) score += _matchScore;
  // Slightly prefer shorter texts among equal matches.
  score -= text.length * 0.05;
  return score;
}
