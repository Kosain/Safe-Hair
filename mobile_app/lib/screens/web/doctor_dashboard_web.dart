import 'package:flutter/material.dart';

import '../doctor_dashboard_redesign_screen.dart';

/// Web entry for doctor shell routes. Delegates to [DoctorDashboardScreen] unchanged.
class DoctorDashboardWeb extends StatelessWidget {
  const DoctorDashboardWeb({super.key, this.section = 'dashboard'});

  final String section;

  @override
  Widget build(BuildContext context) => DoctorDashboardScreen(section: section);
}
