import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../providers/auth_provider.dart';
import '../../providers/doctor_registration_provider.dart';
import '../../providers/theme_provider.dart';

List<SingleChildWidget> buildCoreProviders() {
  return [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ChangeNotifierProvider(create: (_) => DoctorRegistrationProvider()),
  ];
}
