import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/gatekeeper/presentation/screens/gatekeeper_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/gatekeeper',
    redirect: (context, state) {
      final isAuth = authState == AuthState.authenticated;
      final isNeedsGatekeeper = authState == AuthState.needsGatekeeper;
      final isUnauthenticated = authState == AuthState.unauthenticated;
      final isUninitialized = authState == AuthState.uninitialized;

      final isGatekeeperRoute = state.matchedLocation == '/gatekeeper';
      final isAuthRoute = state.matchedLocation == '/auth';

      // If app is still deciding, let it stay on gatekeeper (which can act as a splash)
      if (isUninitialized) return null;

      // If they need gatekeeper, and aren't there, send them there.
      if (isNeedsGatekeeper && !isGatekeeperRoute) {
        return '/gatekeeper';
      }

      // If they passed gatekeeper but need auth, send them to auth
      if (isUnauthenticated && !isAuthRoute) {
        return '/auth';
      }

      // If they are authenticated, send them to dashboard
      if (isAuth) {
        if (isGatekeeperRoute || isAuthRoute) {
          return '/dashboard';
        }
      }

      return null;
    },
    routes: [
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
