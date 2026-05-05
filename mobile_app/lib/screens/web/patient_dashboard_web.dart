import 'package:flutter/material.dart';

import '../patient_dashboard_screen.dart';

/// Web entry for `/dashboard` — same behaviour and layout as [PatientDashboardScreen]
/// (sidebar + wide layout come from [PatientWebScaffold] inside that screen).
/// Use this file for web-specific routing without editing the mobile screen source.
class PatientDashboardWeb extends StatelessWidget {
  const PatientDashboardWeb({super.key});

  @override
  Widget build(BuildContext context) => const PatientDashboardScreen();
}
