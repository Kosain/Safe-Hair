import 'package:flutter/material.dart';

import '../patient_my_scans_screen.dart';

/// Web entry for `/my-scans`. Delegates to [PatientMyScansScreen] unchanged.
class PatientMyScansWeb extends StatelessWidget {
  const PatientMyScansWeb({super.key});

  @override
  Widget build(BuildContext context) => const PatientMyScansScreen();
}
