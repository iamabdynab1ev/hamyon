import 'package:hamyon/database/tables.dart';

// Общие бюджеты работали через чужую базу Firebase. Их заменил собственный
// семейный сервер, где роли, приглашения и общие данные устроены иначе, поэтому
// прежняя реализация удалена.
//
// Функции оставлены заглушками, чтобы не переписывать вызывающий код: возможность
// была выключена настройкой, и он и раньше получал false.

Future<bool> shareBudget(Budget? budgetToShare, context) async => false;

Future<bool> removedSharedFromBudget(Budget sharedBudget,
        {bool removeFromServer = true}) async =>
    false;

Future<bool> leaveSharedBudget(Budget sharedBudget) async => false;

Future<bool> getCloudBudgets() async => false;

Future<bool> sendTransactionSet(Transaction transaction, Budget budget) async =>
    false;

Future<bool> sendTransactionAdd(Transaction transaction, Budget budget) async =>
    false;

Future<bool> sendTransactionDelete(
        Transaction transaction, Budget budget) async =>
    false;

Future<bool> syncPendingQueueOnServer() async => false;

Future<bool> updateTransactionOnServerAfterChangingCategoryInformation(
        TransactionCategory category) async =>
    false;
