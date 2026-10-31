import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_service.dart';
import 'package:zentrip/models/user_model.dart';
import 'package:zentrip/routes/app_routes.dart';

void main() {
  final api = ApiService.instance;
  UserModel? originalUser;

  setUp(() {
    originalUser = api.currentUser;
  });

  tearDown(() {
    api.currentUser = originalUser;
  });

  test('admins are kept inside the admin dashboard routes', () {
    api.currentUser = const UserModel(
      id: 1,
      name: 'Admin',
      email: 'admin@example.com',
      phone: '',
      role: 'admin',
    );

    final homeRoute =
        AppRoutes.onGenerateRoute(const RouteSettings(name: AppRoutes.home));
    final partnerRoute = AppRoutes.onGenerateRoute(
      const RouteSettings(name: AppRoutes.partnerDashboard),
    );

    expect(homeRoute.settings.name, AppRoutes.adminDashboard);
    expect(partnerRoute.settings.name, AppRoutes.adminDashboard);
  });

  test('partners are kept inside the partner dashboard routes', () {
    api.currentUser = const UserModel(
      id: 2,
      name: 'Partner',
      email: 'partner@example.com',
      phone: '',
      role: 'partner',
      partnerId: 10,
    );

    final homeRoute =
        AppRoutes.onGenerateRoute(const RouteSettings(name: AppRoutes.home));
    final adminRoute = AppRoutes.onGenerateRoute(
      const RouteSettings(name: AppRoutes.adminDashboard),
    );

    expect(homeRoute.settings.name, AppRoutes.partnerDashboard);
    expect(adminRoute.settings.name, AppRoutes.partnerDashboard);
  });

  test('customer navigation is unchanged', () {
    api.currentUser = const UserModel(
      id: 3,
      name: 'Customer',
      email: 'customer@example.com',
      phone: '',
    );

    final route =
        AppRoutes.onGenerateRoute(const RouteSettings(name: AppRoutes.home));

    expect(route.settings.name, AppRoutes.home);
  });
}
