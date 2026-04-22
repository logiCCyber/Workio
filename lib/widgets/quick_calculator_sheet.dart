import 'dart:ui';

import 'package:flutter/material.dart';

Future<void> showQuickCalculatorSheet({
  required BuildContext context,
}) async {
  String expression = '';
  String resultText = '0';
  bool justEvaluated = false;

  void appendDigit(String value, void Function(void Function()) setModalState) {
    setModalState(() {
      if (justEvaluated) {
        expression = value;
        justEvaluated = false;
        return;
      }

      expression += value;
    });
  }

  void appendDecimal(void Function(void Function()) setModalState) {
    final match = RegExp(r'(\d*\.?\d*)$').firstMatch(expression);
    final currentSegment = match?.group(0) ?? '';
    if (currentSegment.contains('.')) return;

    setModalState(() {
      if (justEvaluated) {
        expression = '0.';
        justEvaluated = false;
        return;
      }

      if (expression.isEmpty || RegExp(r'[+\-×÷%]$').hasMatch(expression)) {
        expression += '0.';
      } else {
        expression += '.';
      }
    });
  }

  void appendOperator(String op, void Function(void Function()) setModalState) {
    setModalState(() {
      if (expression.isEmpty) {
        if (op == '-') {
          expression = '-';
        }
        return;
      }

      if (RegExp(r'[+\-×÷%.]$').hasMatch(expression)) {
        if (expression.length == 1 && expression == '-') return;
        expression = expression.substring(0, expression.length - 1) + op;
      } else {
        expression += op;
      }

      justEvaluated = false;
    });
  }

  void applyPercent(void Function(void Function()) setModalState) {
    final match = RegExp(r'(-?\d*\.?\d+)$').firstMatch(expression);
    if (match == null) return;

    final rawNumber = match.group(1);
    if (rawNumber == null || rawNumber.isEmpty) return;

    final numericValue = double.tryParse(rawNumber);
    if (numericValue == null) return;

    final replacementValue = _formatCalculatorNumber(numericValue / 100);

    setModalState(() {
      expression = expression.replaceRange(
        match.start,
        match.end,
        replacementValue,
      );
      resultText = replacementValue;
      justEvaluated = false;
    });
  }

  void backspace(void Function(void Function()) setModalState) {
    if (expression.isEmpty) return;
    setModalState(() {
      expression = expression.substring(0, expression.length - 1);
      justEvaluated = false;
    });
  }

  void clearAll(void Function(void Function()) setModalState) {
    setModalState(() {
      expression = '';
      resultText = '0';
      justEvaluated = false;
    });
  }

  void calculate(void Function(void Function()) setModalState) {
    if (expression.isEmpty) return;

    try {
      final value = _evaluateCalculatorExpression(expression);
      final formatted = _formatCalculatorNumber(value);

      setModalState(() {
        expression = formatted;
        resultText = formatted;
        justEvaluated = true;
      });
    } catch (_) {
      setModalState(() {
        resultText = 'Error';
        justEvaluated = true;
      });
    }
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.56),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          String previewText;
          if (expression.isEmpty) {
            previewText = resultText;
          } else {
            try {
              previewText = _formatCalculatorNumber(
                _evaluateCalculatorExpression(expression),
              );
            } catch (_) {
              previewText = resultText == 'Error' ? 'Error' : '—';
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF343741).withOpacity(0.97),
                          const Color(0xFF2A2D35).withOpacity(0.96),
                          const Color(0xFF171A22).withOpacity(0.97),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.10)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.45),
                          blurRadius: 32,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Calculator',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.94),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                onPressed: () => Navigator.pop(sheetContext),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white.withOpacity(0.72),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF20242B),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.white.withOpacity(0.07)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  expression.isEmpty ? '0' : expression,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.78),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  previewText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: previewText == 'Error'
                                        ? const Color(0xFFD46A73)
                                        : Colors.white.withOpacity(0.96),
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _CalculatorKey(
                                      label: 'C',
                                      subtle: true,
                                      onTap: () => clearAll(setModalState),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _CalculatorKey(
                                      label: '%',
                                      subtle: true,
                                      onTap: () => applyPercent(setModalState),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _CalculatorKey(
                                      icon: Icons.backspace_outlined,
                                      subtle: true,
                                      onTap: () => backspace(setModalState),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _CalculatorKey(
                                      label: '÷',
                                      accent: true,
                                      onTap: () => appendOperator('÷', setModalState),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _CalculatorKey(label: '7', onTap: () => appendDigit('7', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '8', onTap: () => appendDigit('8', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '9', onTap: () => appendDigit('9', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '×', accent: true, onTap: () => appendOperator('×', setModalState))),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _CalculatorKey(label: '4', onTap: () => appendDigit('4', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '5', onTap: () => appendDigit('5', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '6', onTap: () => appendDigit('6', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '-', accent: true, onTap: () => appendOperator('-', setModalState))),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _CalculatorKey(label: '1', onTap: () => appendDigit('1', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '2', onTap: () => appendDigit('2', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '3', onTap: () => appendDigit('3', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '+', accent: true, onTap: () => appendOperator('+', setModalState))),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(child: _CalculatorKey(label: '0', onTap: () => appendDigit('0', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '00', onTap: () => appendDigit('00', setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '.', onTap: () => appendDecimal(setModalState))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _CalculatorKey(label: '=', accent: true, onTap: () => calculate(setModalState))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _CalculatorKey extends StatelessWidget {
  const _CalculatorKey({
    this.label,
    this.icon,
    required this.onTap,
    this.accent = false,
    this.subtle = false,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool accent;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = accent
        ? const Color(0xFF3B4351)
        : subtle
            ? const Color(0xFF31353D)
            : const Color(0xFF2B2F36);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent
                  ? Colors.white.withOpacity(0.24)
                  : Colors.white.withOpacity(0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: icon != null
                ? Icon(
                    icon,
                    size: 22,
                    color: Colors.white.withOpacity(accent ? 0.96 : 0.84),
                  )
                : Text(
                    label ?? '',
                    style: TextStyle(
                      color: Colors.white.withOpacity(accent ? 0.96 : 0.88),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

double _evaluateCalculatorExpression(String expression) {
  final parser = _CalculatorExpressionParser(
    expression
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll(' ', ''),
  );
  return parser.parse();
}

String _formatCalculatorNumber(double value) {
  if (value.isNaN || value.isInfinite) return 'Error';

  final normalized = value.abs() < 0.0000000001 ? 0.0 : value;
  final whole = normalized.truncateToDouble();

  if ((normalized - whole).abs() < 0.0000000001) {
    return whole.toInt().toString();
  }

  return normalized
      .toStringAsFixed(10)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

class _CalculatorExpressionParser {
  _CalculatorExpressionParser(this.source);

  final String source;
  int _index = 0;

  double parse() {
    final value = _parseExpression();
    if (_index != source.length) {
      throw const FormatException('Unexpected token');
    }
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();

    while (_match('+') || _match('-')) {
      final operator = source[_index - 1];
      final right = _parseTerm();
      value = operator == '+' ? value + right : value - right;
    }

    return value;
  }

  double _parseTerm() {
    var value = _parseFactor();

    while (_match('*') || _match('/') || _match('%')) {
      final operator = source[_index - 1];
      final right = _parseFactor();

      switch (operator) {
        case '*':
          value *= right;
          break;
        case '/':
          if (right == 0) throw const FormatException('Division by zero');
          value /= right;
          break;
        case '%':
          if (right == 0) throw const FormatException('Division by zero');
          value %= right;
          break;
      }
    }

    return value;
  }

  double _parseFactor() {
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();

    if (_match('(')) {
      final value = _parseExpression();
      if (!_match(')')) throw const FormatException('Missing )');
      return value;
    }

    return _parseNumber();
  }

  double _parseNumber() {
    final start = _index;

    while (_index < source.length && RegExp(r'[0-9.]').hasMatch(source[_index])) {
      _index++;
    }

    if (start == _index) {
      throw const FormatException('Number expected');
    }

    return double.parse(source.substring(start, _index));
  }

  bool _match(String char) {
    if (_index >= source.length || source[_index] != char) return false;
    _index++;
    return true;
  }
}
