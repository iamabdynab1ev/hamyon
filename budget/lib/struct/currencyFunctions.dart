import 'package:hamyon/struct/settings.dart';
import 'dart:convert';
import 'package:hamyon/database/tables.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> currenciesJSON = {};

loadCurrencyJSON() async {
  currenciesJSON = await json.decode(
      await rootBundle.loadString('assets/static/generated/currencies.json'));
}

Future<bool> getExchangeRates() async {
  print("Getting exchange rates for current wallets");
  Map<dynamic, dynamic> cachedCurrencyExchange =
      appStateSettings["cachedCurrencyExchange"];
  try {
    Uri url = Uri.parse(
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json");
    dynamic response = await http.get(url);
    if (response.statusCode == 200) {
      cachedCurrencyExchange = json.decode(response.body)?["usd"];
    }
  } catch (e) {
    print("Error getting currency rates: " + e.toString());
    return false;
  }

  // Мировой источник даёт рыночный курс, а здесь считают по официальному курсу
  // Нацбанка. Для валют из его списка берём его цифры, остальные оставляем как
  // есть: Нацбанк публикует лишь три десятка валют.
  try {
    Map<String, double> nationalBankRates =
        await getNationalBankExchangeRates();
    if (nationalBankRates.isNotEmpty) {
      cachedCurrencyExchange = Map<dynamic, dynamic>.from(cachedCurrencyExchange)
        ..addAll(nationalBankRates);
      print("Applied ${nationalBankRates.length} rates from the national bank");
    }
  } catch (e) {
    print("Error getting national bank rates: " + e.toString());
  }
  // print(cachedCurrencyExchange);
  updateSettings(
    "cachedCurrencyExchange",
    cachedCurrencyExchange,
    updateGlobalState:
        appStateSettings["cachedCurrencyExchange"].keys.length <= 0,
  );
  return true;
}

// Курсы Национального банка Таджикистана. Ответ приходит XML, где для каждой
// валюты указано, сколько сомони стоит Nominal её единиц. Приложение хранит
// курсы в виде «1 доллар = столько-то единиц валюты», поэтому пересчитываем.
Future<Map<String, double>> getNationalBankExchangeRates() async {
  final String today = DateTime.now().toIso8601String().split("T").first;
  final Uri url = Uri.parse(
      "https://nbt.tj/ru/kurs/export_xml.php?export=xmlout&date=" + today);

  final http.Response response =
      await http.get(url).timeout(const Duration(seconds: 20));
  if (response.statusCode != 200) return {};

  // Файл объявляет кодировку windows-1251, но на деле отдаётся в UTF-8,
  // поэтому читаем байты сами, не доверяя заголовку.
  final String body = utf8.decode(response.bodyBytes, allowMalformed: true);

  final RegExp entry = RegExp(
    r"<CharCode>\s*([A-Za-z]{3})\s*</CharCode>\s*"
    r"<Nominal>\s*([\d.]+)\s*</Nominal>[\s\S]*?"
    r"<Value>\s*([\d.]+)\s*</Value>",
  );

  final Map<String, double> somoniPerUnit = {};
  for (final RegExpMatch match in entry.allMatches(body)) {
    final double nominal = double.tryParse(match.group(2) ?? "") ?? 0;
    final double value = double.tryParse(match.group(3) ?? "") ?? 0;
    if (nominal <= 0 || value <= 0) continue;
    somoniPerUnit[(match.group(1) ?? "").toLowerCase()] = value / nominal;
  }

  final double? somoniPerDollar = somoniPerUnit["usd"];
  if (somoniPerDollar == null) return {};

  // Сомони в списке нет — он и есть основа котировок, его курс берём напрямую.
  final Map<String, double> ratesFromDollar = {"tjs": somoniPerDollar};
  somoniPerUnit.forEach((code, perUnit) {
    ratesFromDollar[code] = somoniPerDollar / perUnit;
  });
  return ratesFromDollar;
}

double amountRatioToPrimaryCurrencyGivenPk(
  AllWallets allWallets,
  String walletPk, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (allWallets.indexedByPk[walletPk] == null) return 1;
  return amountRatioToPrimaryCurrency(
    allWallets,
    allWallets.indexedByPk[walletPk]?.currency,
    appStateSettingsPassed: appStateSettingsPassed,
  );
}

double amountRatioToPrimaryCurrency(
  AllWallets allWallets,
  String? walletCurrency, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (walletCurrency == null) {
    return 1;
  }
  if (allWallets
          .indexedByPk[
              (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]]
          ?.currency ==
      walletCurrency) {
    return 1;
  }
  if (allWallets.indexedByPk[
          (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]] ==
      null) {
    return 1;
  }

  double exchangeRateFromUSDToTarget = getCurrencyExchangeRate(
    allWallets
        .indexedByPk[
            (appStateSettingsPassed ?? appStateSettings)["selectedWalletPk"]]
        ?.currency,
    appStateSettingsPassed: appStateSettingsPassed,
  );
  double exchangeRateFromCurrentToUSD = 1 /
      getCurrencyExchangeRate(
        walletCurrency,
        appStateSettingsPassed: appStateSettingsPassed,
      );
  return exchangeRateFromUSDToTarget * exchangeRateFromCurrentToUSD;
}

double? amountRatioFromToCurrency(
    String walletCurrencyBefore, String walletCurrencyAfter) {
  double exchangeRateFromUSDToTarget =
      getCurrencyExchangeRate(walletCurrencyAfter);
  double exchangeRateFromCurrentToUSD =
      1 / getCurrencyExchangeRate(walletCurrencyBefore);
  return exchangeRateFromUSDToTarget * exchangeRateFromCurrentToUSD;
}

// assume selected wallets currency
String getCurrencyString(AllWallets allWallets, {String? currencyKey}) {
  String? selectedWalletCurrency =
      allWallets.indexedByPk[appStateSettings["selectedWalletPk"]]?.currency;
  return currencyKey != null
      ? (currenciesJSON[currencyKey]?["Symbol"] ?? "")
      : selectedWalletCurrency == null
          ? ""
          : (currenciesJSON[selectedWalletCurrency]?["Symbol"] ?? "");
}

double getCurrencyExchangeRate(
  String? currencyKey, {
  Map<String, dynamic>? appStateSettingsPassed,
}) {
  if (currencyKey == null || currencyKey == "") return 1;
  if ((appStateSettingsPassed ?? appStateSettings)["customCurrencyAmounts"]
          ?[currencyKey] !=
      null) {
    return (appStateSettingsPassed ?? appStateSettings)["customCurrencyAmounts"]
            [currencyKey]
        .toDouble();
  } else if ((appStateSettingsPassed ??
          appStateSettings)["cachedCurrencyExchange"]?[currencyKey] !=
      null) {
    return (appStateSettingsPassed ??
            appStateSettings)["cachedCurrencyExchange"][currencyKey]
        .toDouble();
  } else {
    return 1;
  }
}

double budgetAmountToPrimaryCurrency(AllWallets allWallets, Budget budget) {
  return budget.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, budget.walletFk));
}

double objectiveAmountToPrimaryCurrency(
    AllWallets allWallets, Objective objective) {
  return objective.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, objective.walletFk));
}

double categoryBudgetLimitToPrimaryCurrency(
    AllWallets allWallets, CategoryBudgetLimit limit) {
  return limit.amount *
      (amountRatioToPrimaryCurrencyGivenPk(allWallets, limit.walletFk));
}

// Positive (input)
double getAmountRatioWalletTransferTo(AllWallets allWallets, String walletToPk,
    {String? enteredAmountWalletPk}) {
  return amountRatioFromToCurrency(
        allWallets
            .indexedByPk[
                enteredAmountWalletPk ?? appStateSettings["selectedWalletPk"]]!
            .currency!,
        allWallets.indexedByPk[walletToPk]!.currency!,
      ) ??
      1;
}

// Negative (output)
double getAmountRatioWalletTransferFrom(
    AllWallets allWallets, String walletFromPk,
    {String? enteredAmountWalletPk}) {
  return -1 *
      (amountRatioFromToCurrency(
            allWallets
                .indexedByPk[enteredAmountWalletPk ??
                    appStateSettings["selectedWalletPk"]]!
                .currency!,
            allWallets.indexedByPk[walletFromPk]!.currency!,
          ) ??
          1);
}
