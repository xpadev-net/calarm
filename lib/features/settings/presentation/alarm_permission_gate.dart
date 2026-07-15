import 'package:flutter/material.dart';

import '../../../core/platform/native_alarm_gateway.dart';
import '../application/alarm_health_controller.dart';

const alarmPermissionGateKey = ValueKey<String>('alarm-permission-gate');
const alarmPermissionActionKey = ValueKey<String>('alarm-permission-action');
const alarmPermissionRetryKey = ValueKey<String>('alarm-permission-retry');

class AlarmPermissionGate extends StatelessWidget {
  const AlarmPermissionGate({
    super.key,
    required this.state,
    required this.onRequestPermission,
    required this.onRetry,
  });

  final AlarmHealthState? state;
  final Future<void> Function() onRequestPermission;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final health = state;
    final status = health?.readinessStatus ?? AlarmReadinessStatus.checking;
    final content = switch (status) {
      AlarmReadinessStatus.checking => const _GateContent(
        icon: Icons.alarm,
        title: 'Checking alarm access',
        message: 'Calarm is confirming that wake alarms can ring reliably.',
        progress: true,
      ),
      AlarmReadinessStatus.checkFailed => _GateContent(
        icon: Icons.error_outline,
        title: 'Alarm access could not be checked',
        message:
            'The device did not return a valid alarm permission status. '
            'Check the connection to Android system services and try again.',
        action: FilledButton.icon(
          key: alarmPermissionRetryKey,
          onPressed: health?.isBusy == true ? null : onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ),
      AlarmReadinessStatus.actionRequired => _actionRequiredContent(health!),
      AlarmReadinessStatus.ready => const _GateContent(
        icon: Icons.check_circle_outline,
        title: 'Alarm access ready',
        message: 'Opening your calendar…',
        progress: true,
      ),
    };

    return Scaffold(
      key: alarmPermissionGateKey,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: content,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  _GateContent _actionRequiredContent(AlarmHealthState health) {
    final requirement = _nextRequirement(health.capability);
    return _GateContent(
      icon: requirement.icon,
      title: requirement.title,
      message: requirement.message,
      action: FilledButton.icon(
        key: alarmPermissionActionKey,
        onPressed: health.isBusy ? null : onRequestPermission,
        icon: const Icon(Icons.open_in_new),
        label: Text(requirement.actionLabel),
      ),
      progress: health.isRequestingPermission,
    );
  }
}

class _GateContent extends StatelessWidget {
  const _GateContent({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.progress = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (progress) ...[
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
        if (action case final action?) ...[const SizedBox(height: 24), action],
      ],
    );
  }
}

_AlarmRequirement _nextRequirement(NativeAlarmCapability capability) {
  if (capability.requiresExactAlarmPermission) {
    return const _AlarmRequirement(
      icon: Icons.schedule,
      title: 'Allow exact alarms',
      message:
          'Calarm needs exact alarm access so each wake alarm can start at '
          'the selected time. Enable Alarms & reminders in Android settings.',
      actionLabel: 'Open exact alarm settings',
    );
  }
  if (capability.requiresNotificationPermission) {
    return const _AlarmRequirement(
      icon: Icons.notifications_active_outlined,
      title: 'Allow alarm notifications',
      message:
          'Notifications are required to show and control a ringing wake '
          'alarm. Allow notifications when Android asks.',
      actionLabel: 'Allow notifications',
    );
  }
  if (capability.requiresFullScreenIntentPermission) {
    return const _AlarmRequirement(
      icon: Icons.fullscreen,
      title: 'Allow full-screen alarms',
      message:
          'Full-screen alarm access lets the wake screen appear while the '
          'device is locked. Enable it in Android settings.',
      actionLabel: 'Open full-screen settings',
    );
  }
  if (capability.requiresNotificationChannelSetup) {
    return const _AlarmRequirement(
      icon: Icons.tune,
      title: 'Enable the wake alarm channel',
      message:
          'The Wake alarms notification channel is disabled. Turn it on and '
          'allow alarm-style notifications in Android settings.',
      actionLabel: 'Open channel settings',
    );
  }
  return const _AlarmRequirement(
    icon: Icons.alarm_off,
    title: 'Alarm access is required',
    message:
        'Android is not currently allowing Calarm to schedule reliable wake '
        'alarms. Open the available system setting and grant access.',
    actionLabel: 'Open alarm settings',
  );
}

class _AlarmRequirement {
  const _AlarmRequirement({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
}
