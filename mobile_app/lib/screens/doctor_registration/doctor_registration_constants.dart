// Shared constants for consultant (single-doctor) registration.

/// Firebase Storage folder for doctor registration documents.
String consultantRegistrationStoragePrefix(String uid) => 'doctors/$uid/documents';

/// Profile image for doctor onboarding: `doctors/{uid}/profile.jpg` (one object per account).
String doctorOnboardingProfileStoragePath(String uid) => 'doctors/$uid/profile.jpg';

const List<String> kConsultantWeekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

String weekdayTitle(String key) {
  switch (key) {
    case 'monday':
      return 'Monday';
    case 'tuesday':
      return 'Tuesday';
    case 'wednesday':
      return 'Wednesday';
    case 'thursday':
      return 'Thursday';
    case 'friday':
      return 'Friday';
    case 'saturday':
      return 'Saturday';
    case 'sunday':
      return 'Sunday';
    default:
      return key;
  }
}

const List<String> kPakistaniCities = [
  'Karachi',
  'Lahore',
  'Islamabad',
  'Rawalpindi',
  'Faisalabad',
  'Multan',
  'Peshawar',
  'Quetta',
  'Sialkot',
  'Hyderabad',
  'Gujranwala',
  'Bahawalpur',
  'Sargodha',
  'Abbottabad',
  'Mardan',
  'Other',
];

const List<String> kConsultantSpecializations = [
  'Dermatology',
  'Trichology',
  'Hair Transplant',
  'General Physician',
  'Other',
];

/// Preset chips for optional multi-select (Screen 6).
const List<String> kConsultantPresetTimeSlots = [
  '10:00 AM',
  '12:00 PM',
  '2:00 PM',
  '3:00 PM',
  '5:00 PM',
];

const List<int> kRemindBeforeOptionsMinutes = [20, 25, 30, 35, 40];
