// Tajik is not part of the locale data bundled with the intl package, so every
// DateFormat / NumberFormat call made with "tg" throws before this data is
// registered. Month and weekday names here are Tajik; the numeric and pattern
// conventions follow Russian ones, which is what is used in Tajikistan.
// Registration goes through the same public intl API flutter_localizations uses.
import 'package:intl/date_symbol_data_custom.dart' as date_symbol_data_custom;
import 'package:intl/date_symbols.dart';
import 'package:intl/number_symbols.dart';
import 'package:intl/number_symbols_data.dart';

bool _registered = false;

void registerTajikLocaleData() {
  if (_registered) return;
  _registered = true;
  date_symbol_data_custom.initializeDateFormattingCustom(
    locale: "tg",
    symbols: _tajikDateSymbols,
    patterns: _tajikDatePatterns,
  );
  numberFormatSymbols["tg"] = _tajikNumberSymbols;
  compactNumberSymbols["tg"] = _tajikCompactNumberSymbols;
}

final DateSymbols _tajikDateSymbols = DateSymbols(
  NAME: "tg",
  ERAS: <String>["ПеМ", "ПаМ"],
  ERANAMES: <String>["Пеш аз милод", "Пас аз милод"],
  NARROWMONTHS: <String>["Я", "Ф", "М", "А", "М", "И", "И", "А", "С", "О", "Н", "Д"],
  STANDALONENARROWMONTHS: <String>["Я", "Ф", "М", "А", "М", "И", "И", "А", "С", "О", "Н", "Д"],
  MONTHS: <String>["январ", "феврал", "март", "апрел", "май", "июн", "июл",
      "август", "сентябр", "октябр", "ноябр", "декабр"],
  STANDALONEMONTHS: <String>["Январ", "Феврал", "Март", "Апрел", "Май", "Июн",
      "Июл", "Август", "Сентябр", "Октябр", "Ноябр", "Декабр"],
  SHORTMONTHS: <String>["янв", "фев", "мар", "апр", "май", "июн", "июл", "авг",
      "сен", "окт", "ноя", "дек"],
  STANDALONESHORTMONTHS: <String>["Янв", "Фев", "Мар", "Апр", "Май", "Июн",
      "Июл", "Авг", "Сен", "Окт", "Ноя", "Дек"],
  WEEKDAYS: <String>["якшанбе", "душанбе", "сешанбе", "чоршанбе", "панҷшанбе",
      "ҷумъа", "шанбе"],
  STANDALONEWEEKDAYS: <String>["Якшанбе", "Душанбе", "Сешанбе", "Чоршанбе",
      "Панҷшанбе", "Ҷумъа", "Шанбе"],
  SHORTWEEKDAYS: <String>["яшб", "дшб", "сшб", "чшб", "пшб", "ҷум", "шнб"],
  STANDALONESHORTWEEKDAYS: <String>["Яшб", "Дшб", "Сшб", "Чшб", "Пшб", "Ҷум", "Шнб"],
  NARROWWEEKDAYS: <String>["Я", "Д", "С", "Ч", "П", "Ҷ", "Ш"],
  STANDALONENARROWWEEKDAYS: <String>["Я", "Д", "С", "Ч", "П", "Ҷ", "Ш"],
  SHORTQUARTERS: <String>["Ч1", "Ч2", "Ч3", "Ч4"],
  QUARTERS: <String>["Чоряки 1", "Чоряки 2", "Чоряки 3", "Чоряки 4"],
  AMPMS: <String>["ПН", "БН"],
  DATEFORMATS: <String>["EEEE, d MMMM y", "d MMMM y", "d MMM y", "dd.MM.yy"],
  TIMEFORMATS: <String>["HH:mm:ss zzzz", "HH:mm:ss z", "HH:mm:ss", "HH:mm"],
  DATETIMEFORMATS: <String>["{1}, {0}", "{1}, {0}", "{1}, {0}", "{1}, {0}"],
  FIRSTDAYOFWEEK: 0,
  WEEKENDRANGE: <int>[5, 6],
  FIRSTWEEKCUTOFFDAY: 3,
);

const Map<String, String> _tajikDatePatterns = <String, String>{
  'd': 'd',
  'E': 'ccc',
  'EEEE': 'cccc',
  'LLL': 'LLL',
  'LLLL': 'LLLL',
  'M': 'L',
  'Md': 'dd.MM',
  'MEd': 'EEE, dd.MM',
  'MMM': 'LLL',
  'MMMd': 'd MMM',
  'MMMEd': 'ccc, d MMM',
  'MMMM': 'LLLL',
  'MMMMd': 'd MMMM',
  'MMMMEEEEd': 'cccc, d MMMM',
  'QQQ': 'QQQ',
  'QQQQ': 'QQQQ',
  'y': 'y',
  'yM': 'MM.y',
  'yMd': 'dd.MM.y',
  'yMEd': "ccc, dd.MM.y 'г'.",
  'yMMM': "LLL y 'г'.",
  'yMMMd': "d MMM y 'г'.",
  'yMMMEd': "EEE, d MMM y 'г'.",
  'yMMMM': "LLLL y 'г'.",
  'yMMMMd': "d MMMM y 'г'.",
  'yMMMMEEEEd': "EEEE, d MMMM y 'г'.",
  'yQQQ': "QQQ y 'г'.",
  'yQQQQ': "QQQQ y 'г'.",
  'H': 'HH',
  'Hm': 'HH:mm',
  'Hms': 'HH:mm:ss',
  'j': 'HH',
  'jm': 'HH:mm',
  'jms': 'HH:mm:ss',
  'jmv': 'HH:mm v',
  'jmz': 'HH:mm z',
  'jz': 'HH z',
  'm': 'm',
  'ms': 'mm:ss',
  's': 's',
  'v': 'v',
  'z': 'z',
  'zzzz': 'zzzz',
  'ZZZZ': 'ZZZZ',
};

final NumberSymbols _tajikNumberSymbols = NumberSymbols(
  NAME: "tg",
  DECIMAL_SEP: ',',
  GROUP_SEP: '\u00A0',
  PERCENT: '%',
  ZERO_DIGIT: '0',
  PLUS_SIGN: '+',
  MINUS_SIGN: '-',
  EXP_SYMBOL: 'E',
  PERMILL: '\u2030',
  INFINITY: '\u221E',
  NAN: 'NaN',
  DECIMAL_PATTERN: '#,##0.###',
  SCIENTIFIC_PATTERN: '#E0',
  PERCENT_PATTERN: '#,##0\u00A0%',
  CURRENCY_PATTERN: '#,##0.00\u00A0\u00A4',
  DEF_CURRENCY_CODE: 'TJS',
);

final CompactNumberSymbols _tajikCompactNumberSymbols = CompactNumberSymbols(
  COMPACT_DECIMAL_SHORT_PATTERN: const <int, Map<String, String>>{
    3: <String, String>{'other': '0\u00A0ҳаз.'},
    6: <String, String>{'other': '0\u00A0млн'},
    9: <String, String>{'other': '0\u00A0млрд'},
    12: <String, String>{'other': '0\u00A0трлн'},
  },
  COMPACT_DECIMAL_LONG_PATTERN: const <int, Map<String, String>>{
    3: <String, String>{'other': '0 ҳазор'},
    6: <String, String>{'other': '0 миллион'},
    9: <String, String>{'other': '0 миллиард'},
    12: <String, String>{'other': '0 триллион'},
  },
  COMPACT_DECIMAL_SHORT_CURRENCY_PATTERN: const <int, Map<String, String>>{
    3: <String, String>{'other': '0\u00A0ҳаз.\u00A0\u00A4'},
    6: <String, String>{'other': '0\u00A0млн\u00A0\u00A4'},
    9: <String, String>{'other': '0\u00A0млрд\u00A0\u00A4'},
    12: <String, String>{'other': '0\u00A0трлн\u00A0\u00A4'},
  },
);
