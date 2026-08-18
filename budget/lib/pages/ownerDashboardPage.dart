import 'package:hamyon/colors.dart';
import 'package:hamyon/database/tables.dart';
import 'package:hamyon/functions.dart';
import 'package:hamyon/struct/databaseGlobal.dart';
import 'package:hamyon/widgets/framework/pageFramework.dart';
import 'package:hamyon/widgets/settingsContainers.dart';
import 'package:hamyon/widgets/textWidgets.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Сводка для владельца семьи. После синхронизации на его устройстве лежат
// операции всех родных, поэтому всё считается локально, без обращений к серверу.
// Разделение по людям опирается на поле автора, которое проставляется при
// создании операции.

enum DashboardPeriod { month, quarter, year }

class OwnerDashboardPage extends StatefulWidget {
  const OwnerDashboardPage({super.key});

  @override
  State<OwnerDashboardPage> createState() => _OwnerDashboardPageState();
}

class _OwnerDashboardPageState extends State<OwnerDashboardPage> {
  DashboardPeriod period = DashboardPeriod.month;
  DashboardTotals? current;
  DashboardTotals? previous;
  Map<String, String> categoryNames = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  DateTimeRange rangeFor(DashboardPeriod period, {int shiftBack = 0}) {
    final DateTime now = DateTime.now();
    switch (period) {
      case DashboardPeriod.month:
        final DateTime start = DateTime(now.year, now.month - shiftBack, 1);
        return DateTimeRange(
            start: start,
            end: DateTime(start.year, start.month + 1, 1)
                .subtract(const Duration(seconds: 1)));
      case DashboardPeriod.quarter:
        final DateTime start =
            DateTime(now.year, now.month - 2 - shiftBack * 3, 1);
        return DateTimeRange(
            start: start,
            end: DateTime(start.year, start.month + 3, 1)
                .subtract(const Duration(seconds: 1)));
      case DashboardPeriod.year:
        final DateTime start = DateTime(now.year - shiftBack, 1, 1);
        return DateTimeRange(
            start: start,
            end: DateTime(start.year + 1, 1, 1)
                .subtract(const Duration(seconds: 1)));
    }
  }

  Future<void> load() async {
    setState(() => isLoading = true);

    final DateTimeRange currentRange = rangeFor(period);
    final DateTimeRange previousRange = rangeFor(period, shiftBack: 1);

    final List<Transaction> currentTransactions = await database
        .getPaidTransactionsInRange(currentRange.start, currentRange.end);
    final List<Transaction> previousTransactions = await database
        .getPaidTransactionsInRange(previousRange.start, previousRange.end);
    final List<TransactionCategory> categories =
        await database.getAllCategories();

    if (!mounted) return;
    setState(() {
      current = DashboardTotals.from(currentTransactions);
      previous = DashboardTotals.from(previousTransactions);
      categoryNames = {
        for (TransactionCategory category in categories)
          category.categoryPk: category.name
      };
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "owner-dashboard".tr(),
      listWidgets: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
          child: SegmentedButton<DashboardPeriod>(
            segments: [
              ButtonSegment(
                  value: DashboardPeriod.month, label: Text("month".tr())),
              ButtonSegment(
                  value: DashboardPeriod.quarter, label: Text("quarter".tr())),
              ButtonSegment(
                  value: DashboardPeriod.year, label: Text("year".tr())),
            ],
            selected: {period},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setState(() => period = selection.first);
              load();
            },
          ),
        ),
        if (isLoading)
          const Padding(
            padding: EdgeInsetsDirectional.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          DashboardBody(
            current: current!,
            previous: previous!,
            categoryNames: categoryNames,
          ),
      ],
    );
  }
}

class PersonTotals {
  double income = 0;
  double expense = 0;
  int count = 0;
}

class DashboardTotals {
  DashboardTotals({
    required this.income,
    required this.expense,
    required this.count,
    required this.byPerson,
    required this.expenseByCategory,
  });

  final double income;
  final double expense;
  final int count;
  final Map<String, PersonTotals> byPerson;
  final Map<String, double> expenseByCategory;

  double get net => income - expense;

  factory DashboardTotals.from(List<Transaction> transactions) {
    double income = 0;
    double expense = 0;
    final Map<String, PersonTotals> byPerson = {};
    final Map<String, double> expenseByCategory = {};

    for (Transaction transaction in transactions) {
      // Операции, заведённые до подключения сервера, автора не имеют — держим их
      // отдельной строкой, а не приписываем кому-то из родных.
      final String person =
          (transaction.transactionOwnerEmail ?? "").isEmpty
              ? ""
              : transaction.transactionOwnerEmail!;
      final PersonTotals totals =
          byPerson.putIfAbsent(person, () => PersonTotals());
      totals.count += 1;

      if (transaction.income) {
        income += transaction.amount.abs();
        totals.income += transaction.amount.abs();
      } else {
        expense += transaction.amount.abs();
        totals.expense += transaction.amount.abs();
        expenseByCategory[transaction.categoryFk] =
            (expenseByCategory[transaction.categoryFk] ?? 0) +
                transaction.amount.abs();
      }
    }

    return DashboardTotals(
      income: income,
      expense: expense,
      count: transactions.length,
      byPerson: byPerson,
      expenseByCategory: expenseByCategory,
    );
  }
}

class DashboardBody extends StatelessWidget {
  const DashboardBody({
    required this.current,
    required this.previous,
    required this.categoryNames,
    super.key,
  });

  final DashboardTotals current;
  final DashboardTotals previous;
  final Map<String, String> categoryNames;

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, PersonTotals>> people =
        current.byPerson.entries.toList()
          ..sort((a, b) => b.value.expense.compareTo(a.value.expense));

    final List<MapEntry<String, double>> categories =
        current.expenseByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    final AllWallets allWallets = Provider.of<AllWallets>(context);

    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          DashboardAmountRow(
            label: "income".tr(),
            amount: current.income,
            previousAmount: previous.income,
            allWallets: allWallets,
            positiveIsGood: true,
          ),
          DashboardAmountRow(
            label: "expense".tr(),
            amount: current.expense,
            previousAmount: previous.expense,
            allWallets: allWallets,
            positiveIsGood: false,
          ),
          DashboardAmountRow(
            label: "net-total".tr(),
            amount: current.net,
            previousAmount: previous.net,
            allWallets: allWallets,
            positiveIsGood: true,
          ),
          const SizedBox(height: 15),
          DashboardSectionTitle(title: "by-member".tr()),
          if (people.isEmpty)
            DashboardEmpty(text: "no-transactions-found".tr())
          else
            for (MapEntry<String, PersonTotals> person in people)
              SettingsContainer(
                title: person.key.isEmpty ? "unknown-member".tr() : person.key,
                description: "${"expense".tr()}: "
                    "${convertToMoney(allWallets, person.value.expense)}"
                    " · ${"income".tr()}: "
                    "${convertToMoney(allWallets, person.value.income)}"
                    " · ${person.value.count}",
                icon: Icons.person_outline_rounded,
              ),
          const SizedBox(height: 15),
          DashboardSectionTitle(title: "spending-by-category".tr()),
          if (categories.isEmpty)
            DashboardEmpty(text: "no-transactions-found".tr())
          else
            for (MapEntry<String, double> category in categories.take(8))
              SettingsContainer(
                title: categoryNames[category.key] ?? "category".tr(),
                description: convertToMoney(allWallets, category.value),
                icon: Icons.pie_chart_outline_rounded,
              ),
          const SizedBox(height: 25),
        ],
    );
  }
}

class DashboardSectionTitle extends StatelessWidget {
  const DashboardSectionTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 13, bottom: 5),
      child: TextFont(text: title, fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}

class DashboardEmpty extends StatelessWidget {
  const DashboardEmpty({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 13, vertical: 8),
      child: TextFont(
          text: text, fontSize: 14, textColor: getColor(context, "textLight")),
    );
  }
}

class DashboardAmountRow extends StatelessWidget {
  const DashboardAmountRow({
    required this.label,
    required this.amount,
    required this.previousAmount,
    required this.allWallets,
    required this.positiveIsGood,
    super.key,
  });

  final String label;
  final double amount;
  final double previousAmount;
  final AllWallets allWallets;
  final bool positiveIsGood;

  @override
  Widget build(BuildContext context) {
    return SettingsContainer(
      title: label,
      description: convertToMoney(allWallets, amount),
      afterWidget: DashboardChangeLabel(
        amount: amount,
        previousAmount: previousAmount,
        positiveIsGood: positiveIsGood,
      ),
    );
  }
}

class DashboardChangeLabel extends StatelessWidget {
  const DashboardChangeLabel({
    required this.amount,
    required this.previousAmount,
    required this.positiveIsGood,
    super.key,
  });

  final double amount;
  final double previousAmount;
  final bool positiveIsGood;

  @override
  Widget build(BuildContext context) {
    // Без прошлого периода сравнивать не с чем: рост «с нуля» в процентах
    // бесконечен и сбивал бы с толку.
    if (previousAmount == 0) {
      return TextFont(
          text: "—", fontSize: 14, textColor: getColor(context, "textLight"));
    }

    final double change = (amount - previousAmount) / previousAmount.abs() * 100;
    final bool isGood = positiveIsGood ? change >= 0 : change <= 0;

    return TextFont(
      text: (change >= 0 ? "+" : "") + change.toStringAsFixed(0) + "%",
      fontSize: 15,
      fontWeight: FontWeight.bold,
      textColor: isGood
          ? getColor(context, "incomeAmount")
          : getColor(context, "expenseAmount"),
    );
  }
}
