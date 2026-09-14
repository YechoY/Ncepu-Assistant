import 'package:flutter/material.dart';

import '../theme.dart';

class EmptyView extends StatelessWidget {
  final String text;
  const EmptyView({super.key, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(text, style: const TextStyle(fontSize: 13, color: kTextMuted)),
        ),
      );
}
