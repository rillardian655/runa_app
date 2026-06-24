import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB7Nz5o4XcZ1waXsKSEDiiSJRU_xt2oIzE',
    appId: '1:787850092507:web:04dbee19af71b0808b51fe',
    messagingSenderId: '787850092507',
    projectId: 'runaapp-cca6a',
    authDomain: 'runaapp-cca6a.firebaseapp.com',
    storageBucket: 'runaapp-cca6a.firebasestorage.app',
    measurementId: 'G-QWCSG6F5YR',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDPyrAfN-UZc0EfOXbVttklC5eMZ6zXhYw',
    appId: '1:787850092507:android:81790ce35bad5d3a8b51fe',
    messagingSenderId: '787850092507',
    projectId: 'runaapp-cca6a',
    storageBucket: 'runaapp-cca6a.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyApfXS3VvyghfWM4KNlZqQgrTX9q-cp2YQ',
    appId: '1:787850092507:ios:2c445a467a55914b8b51fe',
    messagingSenderId: '787850092507',
    projectId: 'runaapp-cca6a',
    storageBucket: 'runaapp-cca6a.firebasestorage.app',
    iosBundleId: 'com.example.runaApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyApfXS3VvyghfWM4KNlZqQgrTX9q-cp2YQ',
    appId: '1:787850092507:ios:2c445a467a55914b8b51fe',
    messagingSenderId: '787850092507',
    projectId: 'runaapp-cca6a',
    storageBucket: 'runaapp-cca6a.firebasestorage.app',
    iosBundleId: 'com.example.runaApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyB7Nz5o4XcZ1waXsKSEDiiSJRU_xt2oIzE',
    appId: '1:787850092507:web:5f15970b37b1af558b51fe',
    messagingSenderId: '787850092507',
    projectId: 'runaapp-cca6a',
    authDomain: 'runaapp-cca6a.firebaseapp.com',
    storageBucket: 'runaapp-cca6a.firebasestorage.app',
    measurementId: 'G-PVY021ER8E',
  );
}
