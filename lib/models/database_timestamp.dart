String formatDatabaseTimestamp(DateTime value) {
  final DateTime utc = value.toUtc();
  final String year = utc.year.toString().padLeft(4, '0');
  final String month = utc.month.toString().padLeft(2, '0');
  final String day = utc.day.toString().padLeft(2, '0');
  final String hour = utc.hour.toString().padLeft(2, '0');
  final String minute = utc.minute.toString().padLeft(2, '0');
  final String second = utc.second.toString().padLeft(2, '0');
  final String millisecond = utc.millisecond.toString().padLeft(3, '0');
  final String microsecond = utc.microsecond.toString().padLeft(3, '0');
  return '$year-$month-${day}T$hour:$minute:$second.'
      '$millisecond$microsecond'
      'Z';
}
