import 'package:flutter/material.dart';

import 'study_theme.dart';

class FeaturePendingScreen extends StatelessWidget {
  const FeaturePendingScreen({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => StudyTheme(
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_empty, size: 40),
              const SizedBox(height: 24),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回首页'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
