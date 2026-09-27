import 'package:flutter/material.dart';

import '../../app/router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('纯弈国象'),
      actions: [
        IconButton(
          tooltip: '设置',
          onPressed: () => Navigator.pushNamed(context, AppRouter.settings),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_on, size: 64),
            const SizedBox(height: 24),
            Text('一张棋盘，两位棋手', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('与朋友相对而坐，白方先行。'),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.pushNamed(context, AppRouter.game),
              icon: const Icon(Icons.people_outline),
              label: const Text('双人对弈'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, AppRouter.records),
              child: const Text('我的棋谱'),
            ),
          ],
        ),
      ),
    ),
  );
}
