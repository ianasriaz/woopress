import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/gatekeeper/presentation/screens/gatekeeper_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../widgets/splash_screen.dart';
import '../widgets/update_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isAuth = authState == AuthState.authenticated;
      final isNeedsGatekeeper = authState == AuthState.needsGatekeeper;
      final isUnauthenticated = authState == AuthState.unauthenticated;
      final isUninitialized = authState == AuthState.uninitialized;
      final isNeedsUpdate = authState == AuthState.needsUpdate;

      final isSplashRoute = state.matchedLocation == '/splash';
      final isGatekeeperRoute = state.matchedLocation == '/gatekeeper';
      final isAuthRoute = state.matchedLocation == '/auth';
      final isUpdateRoute = state.matchedLocation == '/update';

      // 1. App is checking status in background. Lock to splash.
      if (isUninitialized) {
        return isSplashRoute ? null : '/splash';
      }

      // 2. Forced Update Required. Lock to update.
      if (isNeedsUpdate) {
        return isUpdateRoute ? null : '/update';
      }

      // 3. User needs to enter License Key
      if (isNeedsGatekeeper) {
        return isGatekeeperRoute ? null : '/gatekeeper';
      }

      // 4. User needs to connect WooCommerce store
      if (isUnauthenticated) {
        return isAuthRoute ? null : '/auth';
      }

      // 5. User is fully authenticated, send to dashboard
      if (isAuth) {
        if (isSplashRoute || isGatekeeperRoute || isAuthRoute || isUpdateRoute) {
          return '/dashboard';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/update',
        builder: (context, state) => const UpdateScreen(),
      ),
      GoRoute(
        path: '/gatekeeper',
        builder: (context, state) => const GatekeeperScreen(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      // Add other routes here later
    ],
  );
});
