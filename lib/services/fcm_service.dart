import 'package:firebase_messaging/firebase_messaging.dart';

class FCMService {
  static Future<String?> getToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;


    await messaging.requestPermission();


    String? token = await messaging.getToken();



    return token;
  }
}