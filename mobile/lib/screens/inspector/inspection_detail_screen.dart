import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/inspection_log_models.dart';
import '../../models/scan_models.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/inspection_log_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/verdict.dart';
import '../consumer/scan_capture_screen.dart';
import 'file_report_screen.dart';
import '../../l10n/strings.dart';
import '../../widgets/report_pdf_button.dart';

class InspectionDetailScreen extends StatefulWidget {
  final int evidenceRecordId;
  const InspectionDetailScreen({super.key, required this.evidenceRecordId});

  @override
  State<InspectionDetailScreen> createState() => _InspectionDetailScreenState();
}

class _InspectionDetailScreenState extends State<InspectionDetailScreen> {
  InspectionDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _reportFiled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final d = await context
        .read<InspectionLogProvider>()
        .loadDetail(widget.evidenceRecordId);
    if (!mounted) return;
    setState(() {
      _detail = d;
      _loading = false;
      if (d == null) _error = 'Could not load this record.';
    });
  }

  Future<void> _fileReport() async {
    final detail = _detail;
    if (detail == null) return;
    final filed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FileReportScreen(detail: detail)),
    );
    if (filed == true && mounted) {
      setState(() => _reportFiled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Report sent to the Controller.'))),
      );
    }
  }

  /// A rescan is saved as a new scan linked to this one; this record is
  /// never changed.
  void _rescan() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScanCaptureScreen(rescanOfId: widget.evidenceRecordId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().userRole;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Evidence #{id}', {'id': widget.evidenceRecordId})),
        backgroundColor: Colors.blueGrey.shade900,
        foregroundColor: Colors.white,
        actions: [
          if (_detail != null)
            ReportPdfButton(
                evidenceRecordId: widget.evidenceRecordId, color: Colors.white),
          if (_detail != null)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.replay, size: 18),
              label: Text(tr('Rescan')),
              onPressed: _rescan,
            ),
        ],
      ),
      body: _buildBody(),
      // Filing a report is the inspector's step; a consumer only views.
      floatingActionButton:
          role == UserRole.inspector ? _buildReportFab() : null,
    );
  }

  /// Only offer the report action when there is actually something to
  /// escalate. REVIEW results are not violations — they mean "needs a human",
  /// so a scan with no FAILs and no registry mismatch gets no button rather
  /// than an action that the backend would reject.
  Widget? _buildReportFab() {
    final d = _detail;
    if (d == null) return null;

    // Trust the server: an open report already exists for this scan, so
    // offering to file another would only earn a 400.
    if (_reportFiled || d.hasViolationReport) {
      return FloatingActionButton.extended(
        backgroundColor: AppColors.compliant,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.check_circle_outline),
        label: Text(
          d.violationReportNumber ?? tr('Report filed'),
          style: const TextStyle(fontSize: 13),
        ),
        onPressed: null,
      );
    }

    // A registry mismatch (tampering flag) is also reportable, under Rule
    // 6(3), once the inspector checks the pack on the report screen.
    final count = d.ruleChecks.where((rc) => rc.isFail).length +
        (d.authenticity?.citableMismatches.length ?? 0);
    if (count == 0) return null;

    return FloatingActionButton.extended(
      backgroundColor: AppColors.potentialViolation,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.gavel),
      label: Text(tr('File Report ({n})', {'n': count})),
      onPressed: _fileReport,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final d = _detail!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        if (d.hasViolationReport) _reportBanner(d),
        _verdictHeader(d),
        const SizedBox(height: 12),
        _historyCard(d),
        _evidenceCard(d),
        _rulesCard(d),
        _barcodeCard(d),
        if (d.authenticity != null) _authenticityCard(d.authenticity!),
        if (d.fssaiMark != null) _fssaiCard(d.fssaiMark!),
        _gstinCard(d.gstin),
      ],
    );
  }

  /// Shown when this scan has already been escalated, so the inspector can
  /// see where it sits with the Controller instead of wondering why the
  /// file-report action is gone.
  Widget _reportBanner(InspectionDetail d) {
    final status = d.violationReportStatus ?? '';
    final isDecided = status == 'notice_generated' || status == 'confirmed';
    final color = isDecided ? AppColors.compliant : AppColors.review;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: color.withValues(alpha: 0.08),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          Icon(isDecided ? Icons.gavel : Icons.hourglass_top,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Report {number} filed', {'number': d.violationReportNumber ?? ''}),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: color)),
                Text(
                  status == 'pending_admin_confirmation'
                      ? tr("Awaiting the Controller's review")
                      : status == 'confirmed'
                          ? tr('Confirmed — notice pending')
                          : status == 'notice_generated'
                              ? tr('Legal notice issued')
                              : status.replaceAll('_', ' '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _verdictHeader(InspectionDetail d) {
    final color = Verdict.color(d.overallStatus);
    return Card(
      color: color.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Verdict.icon(d.overallStatus), color: color, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Verdict.label(d.overallStatus),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              Text(tr('{failed}/{total} failed', {'failed': d.failedChecks, 'total': d.totalChecks}),
                  style: TextStyle(
                      color: Colors.grey.shade700, fontSize: 12)),
            ]),
            if (d.productName != null) ...[
              const SizedBox(height: 8),
              Text(d.productName!,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ],
            if (d.actionReason != null) ...[
              const SizedBox(height: 8),
              Text(d.actionReason!, style: const TextStyle(height: 1.3)),
            ],
            if (d.lawReference != null) ...[
              const SizedBox(height: 6),
              Text(d.lawReference!,
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                      color: Colors.grey.shade700)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _evidenceCard(InspectionDetail d) {
    final e = d.evidence;
    return _section(
      title: tr('Chain of Custody'),
      icon: Icons.security,
      color: Colors.blueGrey,
      children: [
        _kv(tr('SHA-256'),
            e.sha256Hash.isEmpty ? '—' : '${e.sha256Hash.substring(0, 16)}…',
            mono: true),
        _kv(tr('Captured'),
            DateFormat('dd MMM yyyy, HH:mm:ss').format(e.timestampDevice)),
        if (e.timestampNtp != null)
          _kv(tr('NTP-verified'),
              DateFormat('dd MMM yyyy, HH:mm:ss').format(e.timestampNtp!)),
        if (e.ntpDriftSeconds != null)
          _kv(tr('NTP drift'), '${e.ntpDriftSeconds!.toStringAsFixed(3)} s'),
        if (e.gpsLatitude != null && e.gpsLongitude != null)
          _kv(tr('GPS'),
              '${e.gpsLatitude!.toStringAsFixed(6)}, ${e.gpsLongitude!.toStringAsFixed(6)}'),
        if (e.gpsAccuracyMeters != null)
          _kv(tr('GPS accuracy'), '± ${e.gpsAccuracyMeters!.round()} m',
              valueColor:
                  e.gpsAccuracyMeters! > 100 ? Colors.orange.shade800 : null),
        if (e.isTampered)
          _kv(tr('Tamper flag'), tr('YES'), valueColor: Colors.red.shade700),
      ],
    );
  }

  /// Who scanned it, its complaint, linked rescans, a re-used photo, and
  /// fields changed from what OCR read.
  Widget _historyCard(InspectionDetail d) {
    final edited = d.editedFields;
    return _section(
      title: tr('Scan history'),
      icon: Icons.history,
      color: Colors.blueGrey,
      children: [
        _kv(tr('Scanned by'),
          d.capturedByUsername == null
              ? '—'
              : '${d.capturedByUsername} (${d.capturedByRole ?? '—'})',
        ),
        if (d.complaintNumber != null)
          _kv(tr('Complaint'),
              '${d.complaintNumber} · ${(d.complaintStatus ?? '').replaceAll('_', ' ')}'),
        if (d.rescanOfId != null) _scanLinks('Rescan of', [d.rescanOfId!]),
        if (d.rescanIds.isNotEmpty) _scanLinks('Rescanned as', d.rescanIds),
        if (d.duplicateOfId != null)
          _scanLinks('Same photo as', [d.duplicateOfId!], warn: true),
        if (d.samePhotoIds.isNotEmpty)
          _scanLinks('Photo re-used in', d.samePhotoIds, warn: true),
        if (edited == null)
          _kv(tr('Edited fields'), tr('Not recorded (scanned before edit tracking)'))
        else if (edited.isEmpty)
          _kv(tr('Edited fields'), tr('None — submitted as OCR read it'))
        else
          ...edited.map((e) => _kv(
                tr('Edited: {field}', {'field': tr(e.label)}),
                '${e.extracted ?? tr('(blank)')} → ${e.submitted ?? tr('(blank)')}',
                valueColor: Colors.orange.shade800,
              )),
      ],
    );
  }

  Widget _scanLinks(String key, List<int> ids, {bool warn = false}) {
    final color = warn ? Colors.orange.shade800 : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(tr(key),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Wrap(
              spacing: 12,
              children: ids
                  .map((id) => InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                InspectionDetailScreen(evidenceRecordId: id),
                          ),
                        ),
                        child: Text(
                          tr('Scan #{id}', {'id': id}),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: color,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rulesCard(InspectionDetail d) {
    if (d.ruleChecks.isEmpty) {
      return _section(
        title: tr('Rule Checks'),
        icon: Icons.rule,
        color: Colors.indigo,
        children: [Text(tr('No individual rule checks recorded.'))],
      );
    }
    return _section(
      title: tr('Rule Checks ({n})', {'n': d.ruleChecks.length}),
      icon: Icons.rule,
      color: Colors.indigo,
      children: d.ruleChecks
          .map((rc) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pill(rc.status),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Rule {n} — {name}', {'n': rc.ruleNumber, 'name': trRuleName(rc.ruleNumber, rc.ruleName)}),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          if (rc.failureReason != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(rc.failureReason!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700)),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(rc.statutoryReference,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _barcodeCard(InspectionDetail d) {
    final found = d.barcode != null && d.barcode!.isNotEmpty;
    return _section(
      title: tr('Barcode'),
      icon: Icons.qr_code_scanner,
      color: found ? Colors.indigo : Colors.grey,
      subtitle: found ? d.barcode! : tr('NOT FOUND'),
      children: [
        _kv(tr('Read by'), tr(barcodeSourceLabel(d.barcode, d.barcodeSource))),
        if (!found) _kv(tr('Effect'), tr('No registry check or font-size measurement for this scan')),
      ],
    );
  }

  Widget _authenticityCard(AuthenticityResultModel a) {
    final subtitle = a.isAuthentic
        ? tr('AUTHENTIC')
        : a.isTampered
            ? tr('TAMPERED SUSPECTED')
            : tr('UNVERIFIED');
    return _section(
      title: tr('Authenticity'),
      icon: Icons.qr_code_2,
      color: a.isAuthentic
          ? Colors.green
          : a.isTampered
              ? Colors.red
              : Colors.grey,
      subtitle: subtitle,
      children: [
        if (a.matchedProductName != null)
          _kv(tr('Registry product'), a.matchedProductName!),
        if (a.message.isNotEmpty) _kv(tr('Note'), a.message),
        if (a.mismatches.isNotEmpty)
          ...a.mismatches.map((m) => _kv(
                m.field,
                tr('expected: {expected}\ndetected: {detected}', {
                  'expected': m.expected ?? '—',
                  'detected': m.detected ?? '—',
                }) + (m.note == null ? '' : '\n${m.note}'),
              )),
      ],
    );
  }

  Widget _fssaiCard(FssaiMarkModel m) {
    final subtitle = switch (m.status) {
      'vegetarian' => tr('VEGETARIAN'),
      'non_vegetarian' => tr('NON-VEGETARIAN'),
      _ => tr('NOT DETECTED'),
    };
    return _section(
      title: tr('FSSAI mark'),
      icon: Icons.circle,
      color: m.status == 'vegetarian'
          ? Colors.green
          : m.status == 'non_vegetarian'
              ? Colors.red
              : Colors.grey,
      subtitle: subtitle,
      children: [
        if (m.foundOn != null) _kv(tr('Found on'), m.foundOn!),
        if (m.photosChecked > 1) _kv(tr('Photos checked'), '${m.photosChecked}'),
        if (m.photosChecked > 1 && m.status == 'not_found')
          _kv(tr('Note'), m.message),
        _kv(tr('Confidence'), m.confidence.toStringAsFixed(2)),
        _kv(tr('Green ratio'), m.greenPixelRatio.toStringAsFixed(3)),
        _kv(tr('Red ratio'), m.redPixelRatio.toStringAsFixed(3)),
      ],
    );
  }

  Widget _gstinCard(GstinModel g) {
    return _section(
      title: tr('GSTIN check'),
      icon: Icons.receipt_long,
      color: g.status.toUpperCase() == 'PASS'
          ? Colors.green
          : g.status.toUpperCase() == 'FAIL'
              ? Colors.red
              : Colors.grey,
      subtitle: trCheckStatus(g.status),
      children: [
        if (g.detectedValue != null) _kv(tr('Detected'), g.detectedValue!),
        if (g.failureReason != null) _kv(tr('Reason'), g.failureReason!),
        _kv(tr('Scope'), g.note),
      ],
    );
  }

  // ── UI building blocks ───────────────────────────────────────────────
  Widget _section({
    required String title,
    required IconData icon,
    required Color color,
    String? subtitle,
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
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              if (subtitle != null)
                Text(subtitle,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w600, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String key, String value,
      {bool mono = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(key,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: valueColor,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String status) {
    final color = switch (status.toUpperCase()) {
      'PASS' => Colors.green,
      'FAIL' => Colors.red,
      'EXEMPT' => Colors.blue,
      _ => Colors.amber,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        trCheckStatus(status),
        style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4),
      ),
    );
  }
}
