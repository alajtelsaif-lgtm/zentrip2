import 'package:flutter/material.dart';
import '../core/services/api_service.dart';
import '../features/splash/presentation/screen/splash_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/auth/presentation/screens/forgot_password_screen.dart';
import '../features/auth/presentation/screens/reset_password_screen.dart';
import '../features/auth/presentation/screens/verfiy_screen.dart.dart';
import '../features/auth/presentation/screens/login_success_screen.dart';
import '../features/trips/presentation/screens/trip_details_screen.dart';
import '../features/trips/presentation/screens/search_flights_screen.dart';
import '../features/trips/presentation/screens/search_hotels_screen.dart';
import '../features/trips/presentation/screens/package_detail_screen.dart';
import '../features/flight_booking/presentation/screens/flight_search_screen.dart';
import '../features/flight_booking/logic/flight_controller.dart';
import '../features/flight_booking/presentation/screens/search_flight_screen.dart';
import '../features/flight_booking/presentation/screens/flight_booking_flow_screen.dart';
import '../features/hotel_booking/presentation/screens/hotel_search_screen.dart';
import '../features/hotel_booking/presentation/screens/hotel_results_screen.dart';
import '../features/hotel_booking/presentation/screens/hotel_detail_screen.dart';
import '../features/car_rental/presentation/screens/car_rental_screen.dart';
import '../features/car_rental/presentation/screens/car_detail_screen.dart';
import '../features/attractions/presentation/screens/attractions_screen.dart';
import '../features/attractions/presentation/screens/attraction_detail_screen.dart';
import '../features/home/presentation/screens/packages_list_screen.dart';
import '../features/transfers/presentation/screens/transfers_screen.dart';
import '../features/profile/presentation/screens/terms_screen.dart';
import '../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../features/admin/presentation/screens/partner_dashboard_screen.dart';
import '../global_widgets/app_shell.dart';
import '../models/travel_package_model.dart';
import '../models/trip_model.dart';

abstract class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String auth = '/auth';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String verifyCode = '/verify-code';
  static const String resetPassword = '/reset-password';
  static const String loginSuccess = '/login-success';
  static const String home = '/home';
  static const String tripDetails = '/trip-details';
  static const String searchFlights = '/search-flights';
  static const String searchHotels = '/search-hotels';
  static const String packageDetail = '/package-detail';
  static const String flightSearch = '/flight-search';
  static const String flightResults = '/flight-results';
  static const String flightBooking = '/flight-booking';
  static const String hotelSearch = '/hotel-search';
  static const String hotelResults = '/hotel-results';
  static const String hotelDetail = '/hotel-detail';
  static const String carRental = '/car-rental';
  static const String carDetail = '/car-detail';
  static const String attractions = '/attractions';
  static const String attractionDetail = '/attraction-detail';
  static const String packagesList = '/packages-list';
  static const String transfers = '/transfers';
  static const String terms = '/terms';
  static const String privacy = '/privacy';
  static const String adminDashboard = '/admin-dashboard';
  static const String partnerDashboard = '/partner-dashboard';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final user = ApiService.instance.currentUser;
    final isDashboardRoute =
        settings.name == adminDashboard || settings.name == partnerDashboard;
    if (isDashboardRoute) {
      if (user == null) {
        return _fade(const LoginScreen(), const RouteSettings(name: auth));
      }
      if (!user.isAdmin && user.role.toLowerCase() != 'partner') {
        return _fade(const AppShell(), const RouteSettings(name: home));
      }
    }
    if (user?.isAdmin == true || user?.role.toLowerCase() == 'partner') {
      final dashboardRoute = user!.isAdmin ? adminDashboard : partnerDashboard;
      if (settings.name != dashboardRoute) {
        final dashboard = user.isAdmin
            ? const AdminDashboardScreen()
            : const PartnerDashboardScreen();
        return _fade(dashboard, RouteSettings(name: dashboardRoute));
      }
    }

    switch (settings.name) {
      case splash:
        return _fade(const SplashScreen(), settings);
      case onboarding:
        return _slide(const OnboardingScreen(), settings);
      case auth:
        return _fade(const LoginScreen(), settings);
      case register:
        return _slide(const RegisterScreen(), settings);
      case forgotPassword:
        return _slide(const ForgotPasswordScreen(), settings);
      case verifyCode:
        final email = settings.arguments;
        if (email is String && email.isNotEmpty) {
          return _slide(VerifyScreen(email: email), settings);
        }
        return _slide(const ForgotPasswordScreen(), settings);
      case resetPassword:
        final email = settings.arguments;
        if (email is String && email.isNotEmpty) {
          return _slide(ResetPasswordScreen(email: email), settings);
        }
        return _slide(const ForgotPasswordScreen(), settings);
      case loginSuccess:
        return _fade(const LoginSuccessScreen(), settings);
      case home:
        return _fade(const AppShell(), settings);
      case tripDetails:
        final argument = settings.arguments;
        if (argument is! TripModel) {
          return _fade(const AppShell(), const RouteSettings(name: home));
        }
        final trip = argument;
        return _slide(TripDetailsScreen(trip: trip), settings);
      case searchFlights:
        return _slide(const SearchFlightsScreen(), settings);
      case searchHotels:
        return _slide(const SearchHotelsScreen(), settings);
      case packageDetail:
        final argument = settings.arguments;
        if (argument is! TravelPackage) {
          return _fade(const AppShell(), const RouteSettings(name: home));
        }
        final pkg = argument;
        return _slide(PackageDetailScreen(package: pkg), settings);
      case flightSearch:
        final args = settings.arguments;
        if (args is FlightSearchRouteArgs) {
          return _slide(
            FlightSearchScreen(
              initialOriginCode: args.originCode,
              initialOriginCity: args.originCity,
              initialDestinationCode: args.destinationCode,
              initialDestinationCity: args.destinationCity,
              initialDepartureDate: args.departureDate,
              initialReturnDate: args.returnDate,
              initialPassengers: args.passengers,
              initialSeatClass: args.seatClass,
              initialRoundTrip: args.roundTrip,
            ),
            settings,
          );
        }
        return _slide(const FlightSearchScreen(), settings);
      case flightResults:
        final args = settings.arguments;
        if (args is FlightSearchParams) {
          return _slide(SearchFlightScreen(initialSearch: args), settings);
        }
        if (args is FlightController) {
          return _slide(SearchFlightScreen(controller: args), settings);
        }
        return _slide(const SearchFlightScreen(), settings);
      case flightBooking:
        return _slide(const FlightBookingFlowScreen(), settings);
      case hotelSearch:
        return _slide(
          HotelSearchScreen(
            initialCity: settings.arguments is String
                ? settings.arguments as String
                : null,
          ),
          settings,
        );
      case hotelResults:
        return _slide(const HotelResultsScreen(), settings);
      case hotelDetail:
        return _slide(const HotelDetailScreen(), settings);
      case carRental:
        return _slide(
          CarRentalScreen(
            initialCity: settings.arguments is String
                ? settings.arguments as String
                : null,
          ),
          settings,
        );
      case carDetail:
        return _slide(const CarDetailScreen(), settings);
      case attractions:
        return _slide(const AttractionsScreen(), settings);
      case attractionDetail:
        return _slide(const AttractionDetailScreen(), settings);
      case packagesList:
        final args = settings.arguments is PackagesListArgs
            ? settings.arguments as PackagesListArgs
            : const PackagesListArgs(kind: PackagesListKind.ideas);
        return _slide(PackagesListScreen(args: args), settings);
      case transfers:
        final args = settings.arguments;
        return _slide(
          TransfersScreen(
            initialFromLocation: args is TransferSearchRouteArgs
                ? args.initialFromLocation
                : null,
            initialToLocation:
                args is TransferSearchRouteArgs ? args.initialToLocation : null,
          ),
          settings,
        );
      case terms:
        return _slide(const TermsScreen(), settings);
      case privacy:
        return _slide(const TermsScreen(showPrivacy: true), settings);
      case adminDashboard:
        return _fade(const AdminDashboardScreen(), settings);
      case partnerDashboard:
        return _fade(const PartnerDashboardScreen(), settings);
      default:
        return _fade(const SplashScreen(), settings);
    }
  }

  // ملحوظة: لازم نمرر settings هنا وإلا أي بيانات مبعوتة عن طريق
  // Navigator.pushNamed(..., arguments: ...) هتضيع تمامًا، لأن الشاشة
  // اللي بتستقبلها بتقراها عن طريق ModalRoute.of(context)?.settings.arguments.
  static PageRouteBuilder _fade(Widget page, [RouteSettings? settings]) =>
      PageRouteBuilder(
        settings: settings,
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  static PageRouteBuilder _slide(Widget page, [RouteSettings? settings]) =>
      PageRouteBuilder(
        settings: settings,
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero)
                  .animate(CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: animation, child: child),
        ),
      );
}
