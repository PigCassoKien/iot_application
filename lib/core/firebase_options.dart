import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Minimal `DefaultFirebaseOptions` for web only.
/// Values copied from `web/index.html` in this project.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return const FirebaseOptions(
        apiKey: 'AIzaSyDvu_3J6hlQ1JEMcXloVc0E_mHOfVacHw0',
        authDomain: 'clothesline-application.firebaseapp.com',
        databaseURL: 'https://clothesline-application-default-rtdb.asia-southeast1.firebasedatabase.app',
        projectId: 'clothesline-application',
        storageBucket: 'clothesline-application.firebasestorage.app',
        messagingSenderId: '874503581558',
        appId: '1:874503581558:web:a6c7795fdb562ef556d457',
        measurementId: 'G-2D98D84ECK',
      );
    }
    throw UnsupportedError('DefaultFirebaseOptions are only supported for web.');
  }
}
