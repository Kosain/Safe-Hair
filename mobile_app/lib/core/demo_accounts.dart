/// FYP demo logins — must match Firebase Auth users in project `safe-hair-274`.
class DemoAccounts {
  DemoAccounts._();

  static const patientEmail = 'moeed123@gmail.com';
  static const patientPassword = 'Moeed123@';

  static const doctorRows = <({String email, String password, String fullName})>[
    (email: 'drayeshakhan123@gmail.com', password: 'drayesha123@', fullName: 'Dr. Ayesha Khan'),
    (email: 'drbilalahmad123@gmail.com', password: 'bilalahmad123@', fullName: 'Dr. Bilal Ahmad'),
    (email: 'drsanatariq123@gmail.com', password: 'sanatariq123@', fullName: 'Dr. Sana Tariq'),
    (email: 'drhamzanoor123@gmail.com', password: 'hamzanoor123@', fullName: 'Dr. Hamza Noor'),
  ];

  static String normEmail(String? email) => (email ?? '').trim().toLowerCase();

  static bool isPatientEmail(String? email) => normEmail(email) == normEmail(patientEmail);

  static bool isDoctorEmail(String? email) {
    final e = normEmail(email);
    return doctorRows.any((d) => normEmail(d.email) == e);
  }

  static ({String fullName, String password})? doctorMeta(String? email) {
    final e = normEmail(email);
    for (final d in doctorRows) {
      if (normEmail(d.email) == e) {
        return (fullName: d.fullName, password: d.password);
      }
    }
    return null;
  }
}
