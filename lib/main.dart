import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'home_screen.dart';

// 1. Define the Global Key once at the top level
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  // 1. MUST come first for Firebase/Plugins to work
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Initialize Firebase BEFORE the app starts
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    print("Firebase initialization failed: $e");
  }

  // 3. Only call runApp ONCE
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 2. IMPORTANT: Attach the key here so your Notifiers can use it
      scaffoldMessengerKey: scaffoldMessengerKey,
      
      title: 'Shot • Stance • Sprawl',
      debugShowCheckedModeBanner: false, // Optional: hides the red banner
      
      theme: ThemeData(
        useMaterial3: true, 
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      
      // Use Dark Mode support since wrestlers often train in dim gyms
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      
      home: const HomeScreen(),
    );
  }
}