// Приложение больше не обращается к чужому проекту Firebase. Функции оставлены,
// чтобы не переписывать вызывающий код: он и раньше умел работать с null.
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

Future<FirebaseFirestore?> firebaseGetDBInstanceAnonymous() async {
  return null;
}

Future<FirebaseFirestore?> firebaseGetDBInstance() async {
  return null;
}
