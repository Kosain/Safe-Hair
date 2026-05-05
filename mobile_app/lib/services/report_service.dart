import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/patient_model.dart';
import '../models/scalp_analysis_result_model.dart';

class ReportService {
  Future<Uint8List> buildSafeHairReport({
    required PatientModel patient,
    required ScalpAnalysisResultModel result,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('My Safe Hair Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('Patient: ${patient.name}'),
          pw.Text('Phone: ${patient.phone}'),
          pw.Text('Location: ${patient.location}'),
          pw.SizedBox(height: 16),
          pw.Text('AI Results', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Severity Grade: ${result.severityGrade}'),
          pw.Text('Estimated Grafts: ${result.graftsRequired}'),
          pw.Text('Confidence: ${(result.confidenceScore * 100).toStringAsFixed(1)}%'),
          pw.SizedBox(height: 8),
          ...result.treatmentSuggestions.map((e) => pw.Bullet(text: e)),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> printReport(Uint8List bytes) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
