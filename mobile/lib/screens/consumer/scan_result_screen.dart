import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/scan_models.dart';
import '../../utils/verdict.dart';
import '../../l10n/strings.dart';
import '../../widgets/report_pdf_button.dart';

/// Full verdict view shown after a consumer scan submission.
class ScanResultScreen extends StatelessWidget {
  final ScanResponse result;
  final String? capturedImagePath;

  const ScanResultScreen({
    super.key,
    required this.result,
    this.capturedImagePath,
  });

  Color get _accent => Verdict.color(result.overallStatus);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Scan Result')),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          ReportPdfButton(
              evidenceRecordId: result.evidenceRecordId, color: Colors.white),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _verdictHeader(),
          const SizedBox(height: 16),
          if (capturedImagePath != null) _thumbnail(),
          if (result.complaintCreated || result.complaintLinked)
            _complaintFiledCard(),
          if (_hasAuditNotes) _auditCard(),
          _barcodeCard(),
          if (result.authenticity != null) _authenticityCard(result.authenticity!),
          if (result.fssaiMark != null) _fssaiCard(result.fssaiMark!),
          _gstinCard(result.gstin),
          _productMetaCard(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: _accent,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Done')),
          ),
        ),
      ),
    );
  }

  Widget _verdictHeader() {
    final icon = Verdict.icon(result.overallStatus);
    final label = Verdict.label(result.overallStatus);
    return Card(
      color: _accent.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _accent, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: _accent, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _accent,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (result.productName != null)
              Text(
                result.productName!,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            if (result.actionReason != null) ...[
              const SizedBox(height: 10),
              Text(result.actionReason!,
                  style: const TextStyle(fontSize: 13, height: 1.35)),
            ],
            if (result.lawReference != null) ...[
              const SizedBox(height: 8),
              Text(tr('Reference: {ref}', {'ref': result.lawReference}),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumbnail() {
    final file = File(capturedImagePath!);
    if (!file.existsSync()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.file(file, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _complaintFiledCard() {
    return Card(
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade400),
      ),
      child: ListTile(
        leading: const Icon(Icons.notifications_active, color: Colors.orange),
        title: Text(result.complaintLinked
            ? tr('Added to your open complaint')
            : tr('Reported to Inspector')),
        subtitle: Text(
          result.complaintLinked
              ? tr('This scan joined complaint {number} instead of opening a new one.',
                  {'number': result.complaintNumber ?? '#${result.complaintId}'})
              : tr('Complaint {number} has been forwarded for review.',
                  {'number': result.complaintNumber ?? '#${result.complaintId}'}),
        ),
      ),
    );
  }

  bool get _hasAuditNotes =>
      result.rescanOfId != null ||
      result.duplicateOfId != null ||
      (result.editedFields?.isNotEmpty ?? false);

  Widget _auditCard() {
    return _sectionCard(
      icon: Icons.history,
      title: tr('On the record'),
      subtitle: tr('Scan #{id}', {'id': result.evidenceRecordId}),
      color: Colors.blueGrey,
      children: [
        if (result.rescanOfId != null)
          _kv(tr('Rescan of'), tr('Scan #{id}, which stays unchanged', {'id': result.rescanOfId})),
        if (result.duplicateOfId != null)
          _kv(tr('Same photo as'),
              tr('Scan #{id}. A re-used photo is not new evidence.', {'id': result.duplicateOfId})),
        ...?result.editedFields?.map((e) => _kv(tr('You changed'),
              '${tr(e.label)}: ${e.extracted ?? tr('(blank)')} → ${e.submitted ?? tr('(blank)')}',
            )),
      ],
    );
  }

  /// The Review Details screen only knows what the phone read, so a barcode
  /// the server found in the photo is shown here, with who read it.
  Widget _barcodeCard() {
    final found = result.barcode != null && result.barcode!.isNotEmpty;
    return _sectionCard(
      icon: Icons.qr_code_scanner,
      title: tr('Barcode'),
      subtitle: found ? result.barcode! : tr('Not found'),
      color: found ? Colors.indigo : Colors.grey.shade700,
      children: [
        _kv(tr('Read by'), tr(barcodeSourceLabel(result.barcode, result.barcodeSource))),
        if (!found)
          _kv(tr('Effect'),
              tr('No registry check or font-size measurement for this scan. '
                  'Hold the pack flat and close, with the barcode in focus.')),
      ],
    );
  }

  Widget _authenticityCard(AuthenticityResultModel auth) {
    final label = auth.isAuthentic
        ? tr('Registry match — authentic')
        : auth.isTampered
            ? tr('Registry match — tampering suspected')
            : tr('Not in reference registry');
    final color = auth.isAuthentic
        ? Colors.green.shade700
        : auth.isTampered
            ? Colors.red.shade700
            : Colors.grey.shade700;
    return _sectionCard(
      icon: Icons.qr_code_2,
      title: tr('Authenticity'),
      subtitle: label,
      color: color,
      children: [
        if (auth.matchedProductName != null)
          _kv(tr('Matched product'), auth.matchedProductName!),
        if (auth.mismatches.isNotEmpty)
          ...auth.mismatches.map(
            (m) => _kv(
              tr('Mismatch • {field}', {'field': m.field}),
              tr('expected: {expected}\ndetected: {detected}',
                  {'expected': m.expected ?? '—', 'detected': m.detected ?? '—'}),
            ),
          ),
        if (auth.message.isNotEmpty) _kv(tr('Note'), auth.message),
      ],
    );
  }

  Widget _fssaiCard(FssaiMarkModel mark) {
    final label = switch (mark.status) {
      'vegetarian' => tr('Vegetarian mark detected'),
      'non_vegetarian' => tr('Non-vegetarian mark detected'),
      _ => tr('FSSAI mark not detected'),
    };
    return _sectionCard(
      icon: Icons.circle,
      title: tr('FSSAI veg/non-veg mark'),
      subtitle: label,
      color: mark.status == 'vegetarian'
          ? Colors.green
          : mark.status == 'non_vegetarian'
              ? Colors.red
              : Colors.grey,
      children: [
        if (mark.foundOn != null) _kv(tr('Found on'), mark.foundOn!),
        if (mark.photosChecked > 1)
          _kv(tr('Photos checked'), '${mark.photosChecked}'),
        if (mark.photosChecked > 1 && mark.status == 'not_found')
          _kv(tr('Note'), mark.message),
        _kv(tr('Confidence'), mark.confidence.toStringAsFixed(2)),
        _kv(tr('Green pixel ratio'), mark.greenPixelRatio.toStringAsFixed(3)),
        _kv(tr('Red pixel ratio'), mark.redPixelRatio.toStringAsFixed(3)),
      ],
    );
  }

  Widget _gstinCard(GstinModel gstin) {
    final passed = gstin.status.toUpperCase() == 'PASS';
    final color = passed
        ? Colors.green
        : gstin.status.toUpperCase() == 'FAIL'
            ? Colors.red
            : Colors.grey;
    return _sectionCard(
      icon: Icons.receipt_long,
      title: tr('GSTIN check'),
      subtitle: trCheckStatus(gstin.status),
      color: color,
      children: [
        if (gstin.detectedValue != null) _kv(tr('Detected'), gstin.detectedValue!),
        if (gstin.failureReason != null) _kv(tr('Reason'), gstin.failureReason!),
        _kv(tr('Scope'), gstin.note),
      ],
    );
  }

  Widget _productMetaCard() {
    return _sectionCard(
      icon: Icons.receipt,
      title: tr('Record'),
      subtitle: tr('Evidence #{id}', {'id': result.evidenceRecordId}),
      color: Colors.indigo,
      children: [
        _kv(tr('Compliance record'), '#${result.complianceResultId}'),
        _kv(tr('Failed rule checks'),
            result.failedRuleCheckIds.isEmpty ? tr('None') : result.failedRuleCheckIds.join(', ')),
      ],
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              Text(subtitle,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(key,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
