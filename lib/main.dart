import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'core/router/app_router.dart';

import 'package:firebase_core/firebase_core.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/network/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCmsdZtC_Uld2WuG4clHJA5DNmy_lsfUn0',
        appId: '1:340044289106:android:600b27e8c6a4f13446fb8b',
        messagingSenderId: '340044289106',
        projectId: 'wooexpress',
        databaseURL: 'https://wooexpress-default-rtdb.asia-southeast1.firebasedatabase.app',
      ),
    );
  } catch (e) {
    print('Firebase Init Error: $e');
  }

  final container = ProviderContainer();

  // Initialize Background Sync Engine for offline support
  container.read(syncServiceProvider).startListening();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WooPressApp(),
    ),
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class WooPressApp extends ConsumerWidget {
  const WooPressApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      routerConfig: router,
      title: 'WooPress',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: FlexThemeData.light(
        scheme: FlexScheme.blue,
        surfaceMode: FlexSurfaceMode.highSurfaceLowScaffold,
        blendLevel: 0,
        appBarStyle: FlexAppBarStyle.background,
        bottomAppBarElevation: 0.0,
        scaffoldBackground: const Color(0xFFF5F5F7), // Apple-like light gray
        surface: const Color(0xFFFFFFFF),
        onSurface: const Color(0xFF000000),
        primary: const Color(0xFF000000),
        onPrimary: const Color(0xFFFFFFFF),
        typography: Typography.material2021(),
        useMaterial3: true,
      ).copyWith(
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
          ),
        ),
      ),
    );
  }
}
