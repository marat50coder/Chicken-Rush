String formatAmount(double value) {
  final cents = (value * 100).round();
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = abs % 100;

  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }

  var result = buf.toString();
  if (frac != 0) {
    var f = frac.toString().padLeft(2, '0');
    if (f.endsWith('0')) f = f.substring(0, 1);
    result = '$result.$f';
  }
  return negative ? '-$result' : result;
}

String formatMultiplier(double m) {
  if (m >= 1000) return '${formatAmount(m)}x';
  return '${m.toStringAsFixed(2)}x';
}
