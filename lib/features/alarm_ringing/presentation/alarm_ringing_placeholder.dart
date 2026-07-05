import 'package:flutter/material.dart';

class AlarmRingingPlaceholder extends StatelessWidget {
  const AlarmRingingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _FeatureTile(
      title: 'Alarm ringing',
      subtitle: 'Boundary for active ringing and dismissal flows.',
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}
