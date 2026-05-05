import 'package:flutter/material.dart';

import '../patient_my_report_screen.dart';

/// Web entry for `/my-report`. Delegates to [PatientMyReportScreen] unchanged.
class PatientMyReportWeb extends StatelessWidget {
  const PatientMyReportWeb({super.key});

  @override
  Widget build(BuildContext context) => const PatientMyReportScreen();
}
