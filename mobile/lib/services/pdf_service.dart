import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

/// Downloads PDFs and opens them with the OS's default viewer.
class PdfService {
  final ApiService api;

  PdfService(this.api);

  /// Fetches the notice for [evidenceRecordId], saves it under the app's
  /// temporary directory, and launches the platform PDF viewer.
  ///
  /// Returns the local file path (already opened) or throws on failure.
  Future<String> downloadAndOpenLegalNotice(int evidenceRecordId) async {
    final result = await api.downloadLegalNotice(evidenceRecordId);
    return _saveAndOpen(result.bytes, result.filename);
  }

  /// The scan summary in [lang] ("en" or "ta"), saved and opened.
  Future<String> downloadAndOpenScanSummary(int evidenceRecordId, String lang) async {
    final result = await api.downloadScanSummary(evidenceRecordId, lang);
    return _saveAndOpen(result.bytes, result.filename);
  }

  Future<String> _saveAndOpen(List<int> bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final outFile = File('${dir.path}/$safeName');
    await outFile.writeAsBytes(bytes, flush: true);

    final open = await OpenFilex.open(outFile.path, type: 'application/pdf');
    if (open.type != ResultType.done) {
      throw Exception('Could not open PDF viewer: ${open.message}');
    }
    return outFile.path;
  }
}
