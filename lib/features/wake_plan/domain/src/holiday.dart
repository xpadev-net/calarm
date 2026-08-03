import '../../../../core/time/time.dart';

class Holiday {
  const Holiday({required this.date, required this.name});

  final CalendarDay date;
  final String name;

  @override
  bool operator ==(Object other) {
    return other is Holiday && date == other.date && name == other.name;
  }

  @override
  int get hashCode => Object.hash(date, name);

  @override
  String toString() => 'Holiday($date, $name)';
}
