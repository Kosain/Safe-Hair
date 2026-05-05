import 'package:flutter/material.dart';

import '../patient_my_appointments_screen.dart';

/// Web entry for `/my-appointments`. Delegates to [PatientMyAppointmentsScreen] unchanged.
class PatientMyAppointmentsWeb extends StatelessWidget {
  const PatientMyAppointmentsWeb({super.key});

  @override
  Widget build(BuildContext context) => const PatientMyAppointmentsScreen();
}
