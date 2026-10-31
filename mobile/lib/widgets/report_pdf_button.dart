import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api_service.dart';
import '../services/pdf_service.dart';

/// Opens the scan summary PDF in the app's language setting (English or
/// Tamil). A long press offers the other language as well.
class ReportPdfButton extends StatefulWidget {
  final int evidenceRecordId;
  final Color? color;

  const ReportPdfButton({super.key, required this.evidenceRecordId, this.color});

  @override
  State<ReportPdfButton> createState() => _ReportPdfButtonState();
}

class _ReportPdfButtonState extends State<ReportPdfButton> {
  bool _busy = false;
  // Where the finger went down, so the language menu opens under it.
  Offset _touchedAt = Offset.zero;

  Future<void> _open(String lang) async {
    setState(() => _busy = true);
    try {
      await PdfService(ApiService()).downloadAndOpenScanSummary(widget.evidenceRecordId, lang);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not open the report: {error}', {'error': e}))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseLanguage(Offset at) async {
    final lang = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: const [
        PopupMenuItem(value: 'ta', child: Text('தமிழ் PDF')),
        PopupMenuItem(value: 'en', child: Text('English PDF')),
      ],
    );
    if (lang != null) await _open(lang);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tr('Report in the app language. Long-press for the other language.'),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTapDown: (d) => _touchedAt = d.globalPosition,
        onTap: _busy ? null : () => _open(AppLanguage.code),
        onLongPress: _busy ? null : () => _chooseLanguage(_touchedAt),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: widget.color),
                  )
                : Icon(Icons.picture_as_pdf_outlined, size: 20, color: widget.color),
            const SizedBox(width: 4),
            Text(tr('Report'), style: TextStyle(color: widget.color, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
