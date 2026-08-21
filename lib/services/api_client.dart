String encodeLogin(String username, String password, String dataStr) {
  final String sep;
  if (dataStr.contains('#')) {
    sep = '#';
  } else if (dataStr.contains(';')) {
    sep = ';';
  } else if (dataStr.contains('|')) {
    sep = '|';
  } else {
    throw ArgumentError('无法解析登录种子: ${dataStr.length > 60 ? dataStr.substring(0, 60) : dataStr}');
  }
  final parts = dataStr.split(sep);
  var scode = parts[0];
  final sxh = parts[1];
  final code = username + '%%%' + password;
  final buf = StringBuffer();
  for (var i = 0; i < code.length; i++) {
    final n = i < sxh.length && int.tryParse(sxh[i]) != null ? int.parse(sxh[i]) : 0;
    buf.write(code[i]);
    if (n > 0 && scode.length >= n) {
      buf.write(scode.substring(0, n));
      scode = scode.substring(n);
    }
  }
  return buf.toString();
}
