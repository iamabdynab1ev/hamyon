// Проверяет разбор курсов Национального банка Таджикистана на живом ответе.
// Запуск: flutter test test/exchangeRatesTest.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hamyon/struct/currencyFunctions.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Биндинг тестов подменяет HttpClient заглушкой, отвечающей 400.
    HttpOverrides.global = null;
  });

  test("курсы Нацбанка разбираются и пересчитываются от доллара", () async {
    final Map<String, double> rates = await getNationalBankExchangeRates();

    expect(rates.isNotEmpty, true, reason: "список курсов пуст");
    expect(rates.containsKey("tjs"), true, reason: "нет сомони");
    expect(rates.containsKey("usd"), true);

    // Доллар к самому себе всегда единица
    expect(rates["usd"]!, closeTo(1, 0.0001));

    // Сомони: несколько единиц за доллар, но не десятки тысяч
    expect(rates["tjs"]!, greaterThan(5));
    expect(rates["tjs"]!, lessThan(30));

    // Номинал учтён: сум котируется за 100 единиц, без пересчёта
    // курс отличался бы в сто раз
    expect(rates["uzs"]!, greaterThan(1000));

    // Рубль и евро в разумных пределах
    expect(rates["rub"]!, greaterThan(20));
    expect(rates["eur"]!, greaterThan(0.5));
    expect(rates["eur"]!, lessThan(2));

    print("сомони за доллар: ${rates["tjs"]!.toStringAsFixed(4)}"
        " | валют получено: ${rates.length}");
  });
}
