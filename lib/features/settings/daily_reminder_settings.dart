import 'package:flutter/material.dart';

import '../../app/notifications.dart';

class DailyReminderTiles extends StatelessWidget {
  const DailyReminderTiles({super.key, required this.service});

  final DailyReminderService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final settings = service.settings;
      final time = TimeOfDay(hour: settings.hour, minute: settings.minute);
      final available = service.supported && !service.busy;
      return Column(
        children: [
          SwitchListTile(
            key: const ValueKey('daily-reminder-toggle'),
            title: const Text('每日战术题提醒'),
            subtitle: Text(
              service.supported ? '每天提醒你练习战术题，可随时关闭' : '当前平台暂不支持本地提醒',
            ),
            value: settings.enabled && service.supported,
            onChanged: available
                ? (enabled) => service.update(
                    DailyReminderSettings(
                      enabled: enabled,
                      hour: settings.hour,
                      minute: settings.minute,
                    ),
                  )
                : null,
          ),
          ListTile(
            title: const Text('提醒时间'),
            trailing: Text(
              '${settings.hour.toString().padLeft(2, '0')}:'
              '${settings.minute.toString().padLeft(2, '0')}',
            ),
            enabled: available,
            onTap: !available
                ? null
                : () async {
                    final selected = await showTimePicker(
                      context: context,
                      initialTime: time,
                      helpText: '选择提醒时间',
                      cancelText: '取消',
                      confirmText: '确定',
                      hourLabelText: '时',
                      minuteLabelText: '分',
                      errorInvalidText: '请输入有效时间',
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(alwaysUse24HourFormat: true),
                        child: child!,
                      ),
                    );
                    if (selected == null || !context.mounted) return;
                    await service.update(
                      DailyReminderSettings(
                        enabled: service.settings.enabled,
                        hour: selected.hour,
                        minute: selected.minute,
                      ),
                    );
                  },
          ),
          if (service.error != null)
            ListTile(
              title: Text(
                service.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              trailing: TextButton(
                onPressed: service.busy ? null : service.retry,
                child: const Text('重试'),
              ),
            ),
        ],
      );
    },
  );
}
