import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets('Fetch users from Firestore', (WidgetTester tester) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyBhXMt6b8Ih44h6fQ1sCErS6mqExp8wJAI',
        appId: '1:762306964857:web:9cbdd52195759875c113a8',
        messagingSenderId: '762306964857',
        projectId: 'runa-f1e8e',
        authDomain: 'runa-f1e8e.firebaseapp.com',
        storageBucket: 'runa-f1e8e.firebasestorage.app',
        measurementId: 'G-VQX24PJMPJ',
      ),
    );

    final firestore = FirebaseFirestore.instance;
    final snapshot = await firestore.collection('users').get();
    print('TOTAL USERS: ${snapshot.docs.length}');
    for (var doc in snapshot.docs) {
      print('USER: ${doc.id} => ${doc.data()}');
    }
  });
}
