import 'package:flutter/material.dart';

import '../models/inspection_log_models.dart';
import '../l10n/strings.dart';

/// Small chips for a scan's audit context: a rescan, a re-used photo, label
/// fields the user changed from what OCR read, and its complaint.
class ScanFlags extends StatelessWidget {
  final InspectionLogRow row;

  const ScanFlags({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final edited = row.editedFields ?? const <String>[];
    final chips = <Widget>[
      if (row.rescanOfId != null)
        _chip(Icons.replay, tr('Rescan of #{id}', {'id': row.rescanOfId}), Colors.indigo),
      if (row.duplicateOfId != null)
        _chip(Icons.content_copy, tr('Same photo as #{id}', {'id': row.duplicateOfId}),
            Colors.deepOrange),
      if (edited.isNotEmpty)
        _chip(
          Icons.edit_note,
          tr('Edited: {field}', {'field': edited.map((f) => tr(f.replaceAll('_', ' '))).join(', ')}),
          Colors.orange.shade800,
        ),
      if (row.complaintNumber != null)
        _chip(
          Icons.flag_outlined,
          '${row.complaintNumber} · ${(row.complaintStatus ?? '').replaceAll('_', ' ')}',
          Colors.blueGrey,
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
