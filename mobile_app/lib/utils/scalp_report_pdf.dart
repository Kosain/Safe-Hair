import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

pw.Widget _pdfMarkCircle(PdfColor border, PdfColor fill) {
  return pw.Container(
    width: 24,
    height: 24,
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      border: pw.Border.all(color: border, width: 2),
      color: fill,
    ),
  );
}

/// Builds a multi-section scalp analysis PDF for sharing / printing.
Future<Uint8List> buildScalpAnalysisReportPdf({
  required String patientName,
  required String dateStr,
  required String timeStr,
  required int patientAge,
  required String patientGender,
  required int overallScore,
  required int strength,
  required int scalp,
  required int damage,
  required int fall,
  required String graftEstimateText,
  required List<Map<String, dynamic>> issues,
  required List<String> recommendations,
  Uint8List? scalpImageBytes,
}) async {
  final doc = pw.Document();

  pw.Widget? scalpBlock;
  if (scalpImageBytes != null && scalpImageBytes.isNotEmpty) {
    final img = pw.MemoryImage(scalpImageBytes);
    scalpBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Scalp photo (highlighted)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.SizedBox(
          width: double.infinity,
          height: 200,
          child: pw.Stack(
            children: [
              pw.Positioned.fill(child: pw.Image(img, fit: pw.BoxFit.cover)),
              pw.Positioned(left: 16, top: 40, child: _pdfMarkCircle(PdfColors.red900, PdfColors.red100)),
              pw.Positioned(left: 96, top: 68, child: _pdfMarkCircle(PdfColor.fromInt(0xFFE65100), PdfColors.yellow100)),
              pw.Positioned(right: 18, bottom: 28, child: _pdfMarkCircle(PdfColor.fromInt(0xFF00897B), PdfColor.fromInt(0xFFB2DFDB))),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'High risk – red circle | Dandruff / irritation – yellow circle | Low density / mild thinning – teal circle',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      build: (ctx) => [
        pw.Text(
          'AI Scalp Analysis Report',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          '$dateStr at $timeStr',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.normal, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Patient: $patientName | Age: $patientAge | Gender: $patientGender',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Text('Overall hair health score', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          '$overallScore / 100',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Hair Strength: $strength% | Scalp Health: $scalp% | Hair Damage: $damage% | Hair Fall Risk: $fall%',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey900),
        ),
        pw.SizedBox(height: 12),
        if (scalpBlock != null) scalpBlock,
        pw.Text('Detected issues', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(0.7),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _pdfCell('Issue', header: true),
                _pdfCell('Severity', header: true),
                _pdfCell('Location', header: true),
                _pdfCell('Recommendation', header: true),
                _pdfCell('Conf. %', header: true),
              ],
            ),
            ...issues.map(
              (row) => pw.TableRow(
                children: [
                  _pdfCell(row['issue']?.toString() ?? ''),
                  _pdfCell(row['severity']?.toString() ?? ''),
                  _pdfCell(row['location']?.toString() ?? ''),
                  _pdfCell(row['recommendation']?.toString() ?? ''),
                  _pdfCell('${row['confidencePct'] ?? ''}%'),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('Estimated grafts needed: $graftEstimateText', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        pw.SizedBox(height: 12),
        pw.Text('Personalized recommendations', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        ...recommendations.map(
          (r) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Container(
                    width: 5,
                    height: 5,
                    decoration: const pw.BoxDecoration(color: PdfColors.black, shape: pw.BoxShape.circle),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(child: pw.Text(r, style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.35))),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'This is an AI-generated report for informational purposes only. Not a substitute for professional medical advice.',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ],
    ),
  );
  return Uint8List.fromList(await doc.save());
}

pw.Widget _pdfCell(String text, {bool header = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: header ? 9 : 9,
        fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}
