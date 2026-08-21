class Grade {
  final String term, name, grade, attr, credit;
  const Grade({
    required this.term,
    required this.name,
    required this.grade,
    required this.attr,
    required this.credit,
  });
  factory Grade.fromJson(Map<String, dynamic> j) => Grade(
    term: j['term'] as String? ?? '',
    name: j['name'] as String? ?? '',
    grade: j['grade'] as String? ?? '',
    attr: j['attr'] as String? ?? '',
    credit: j['credit'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'term': term,
    'name': name,
    'grade': grade,
    'attr': attr,
    'credit': credit,
  };
}
