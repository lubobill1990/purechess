import 'package:flutter/material.dart';

/// Compatibility wrapper; reading pages now inherit the global app theme.
class StudyTheme extends StatelessWidget {
  const StudyTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
