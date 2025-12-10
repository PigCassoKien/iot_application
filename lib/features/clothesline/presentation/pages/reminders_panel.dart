import 'package:flutter/material.dart';

class RemindersPanel extends StatelessWidget {
  final List<Map<String, dynamic>> reminders;
  final VoidCallback onAddReminder;
  final void Function(String id) onMarkDone;

  const RemindersPanel({super.key, required this.reminders, required this.onAddReminder, required this.onMarkDone});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Expanded(child: Text('Nhắc nhở', style: TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Flexible(flex: 0, child: TextButton.icon(onPressed: onAddReminder, icon: const Icon(Icons.add), label: const Text('Thêm'))),
          ]),
          const SizedBox(height: 8),
          if (reminders.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Chưa có nhắc nhở', style: TextStyle(color: Colors.grey[700])))
          else
            Column(children: reminders.take(8).map((r) {
              final id = r['id'] as String;
              final title = r['title'] as String;
              final when = r['when'] as int;
              final done = r['done'] as bool;
              final dt = when > 0 ? DateTime.fromMillisecondsSinceEpoch(when).toLocal().toString().split('.').first : '—';
              return ListTile(
                dense: true,
                title: Text(title, style: TextStyle(decoration: done ? TextDecoration.lineThrough : TextDecoration.none)),
                subtitle: Text(dt),
                trailing: done ? const Icon(Icons.check, color: Colors.green) : IconButton(icon: const Icon(Icons.check_circle_outline), onPressed: () => onMarkDone(id)),
              );
            }).toList()),
        ]),
      ),
    );
  }
}
