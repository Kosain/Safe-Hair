/// Default doctors list - shown when API is unavailable
class DoctorsData {
  static List<Map<String, dynamic>> get defaultDoctors => [
    {
      'id': '1',
      'name': 'Dr. Daniyal Ahmad',
      'location': 'Johar Town, Lahore',
      'rating': 4.0,
      'consultationFee': 12000,
    },
    {
      'id': '2',
      'name': 'Dr. Hina Alam',
      'location': 'DHA Rahbar, Lahore',
      'rating': 5.0,
      'consultationFee': 13500,
    },
    {
      'id': '3',
      'name': 'Dr. Ammar Hassan',
      'location': 'Samnabad, Lahore',
      'rating': 4.5,
      'consultationFee': 12500,
    },
    {
      'id': '4',
      'name': 'Dr. Ayesha Hassan',
      'location': 'Lake City, Lahore',
      'rating': 4.5,
      'consultationFee': 11800,
    },
  ];
}
