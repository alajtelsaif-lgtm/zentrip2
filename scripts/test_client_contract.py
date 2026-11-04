"""Static checks for Flutter endpoint calls and Spring route/security contracts."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
API_CLIENT = (ROOT / "lib/core/services/api_service.dart").read_text()
API_CONTROLLER = (
    ROOT / "backend/src/main/java/com/zentrip/api/ApiController.java"
).read_text()
SECURITY = (
    ROOT / "backend/src/main/java/com/zentrip/api/SecurityConfig.java"
).read_text()
WEB_CONFIG = (
    ROOT / "backend/src/main/java/com/zentrip/api/WebConfig.java"
).read_text()


def section(source: str, start: str, end: str) -> str:
    first = source.index(start)
    last = source.index(end, first)
    return source[first:last]


class ClientApiContractTest(unittest.TestCase):
    def test_unsupported_live_calls_are_disabled_or_removed(self):
        social = section(
            API_CLIENT,
            "Future<ApiResult<UserModel>> loginWithSocial(",
            "Future<MultipartFile> _profilePhotoPart",
        )
        weather = section(
            API_CLIENT,
            "Future<ApiResult<WeatherInfo>> getDestinationWeather(",
            "// ── التقييمات (Reviews)",
        )
        cars = section(
            API_CLIENT,
            "Future<List<CarModel>> searchCars(",
            "Future<List<String>> searchCarLocations(",
        )
        transfers = section(
            API_CLIENT,
            "Future<List<TransferModel>> searchTransfers(",
            "/// Fetches verified landmark categories",
        )

        self.assertIn("if (!socialAuthConfigured)", social)
        social_route = social.index("'/auth/social-login'")
        self.assertLess(social.index("if (!socialAuthConfigured)"), social_route)
        self.assertIn("static const bool socialAuthConfigured = false;", API_CLIENT)
        self.assertNotIn("'/destinations/weather'", weather)
        self.assertNotIn("'/destinations/visa-info'", weather)
        self.assertIn("isSample: true", weather)
        self.assertIn("ApiResult<WeatherInfo>.failure", weather)
        self.assertIn("ApiResult<VisaInfo>.failure", weather)
        self.assertNotIn("'/cars/search'", cars)
        self.assertNotIn("'/transfers/search'", transfers)
        self.assertIn("return partnerCars;", cars)
        self.assertIn("return partnerTransfers;", transfers)

    def test_push_token_client_and_server_contract_matches(self):
        registration = section(
            API_CLIENT,
            "Future<ApiResult<void>> registerFcmToken(",
            "// ── AI Chatbot",
        )
        self.assertIn("'/users/fcm-token'", registration)
        self.assertIn("'/users/fcm-token'", API_CLIENT)
        self.assertIn('@PostMapping("/users/fcm-token")', API_CONTROLLER)
        self.assertIn('@DeleteMapping("/users/fcm-token")', API_CONTROLLER)
        self.assertIn('"/api/users/fcm-token"', SECURITY)

    def test_nearby_attractions_are_explicitly_public_and_rate_limited(self):
        self.assertIn('"/api/attractions/nearby"', SECURITY)
        self.assertIn("REQUEST_SPACING_NANOS", (
            ROOT / "backend/src/main/java/com/zentrip/api/"
            "OpenTripMapAttractionService.java"
        ).read_text())
        self.assertIn("waitForRequestSlot();", (
            ROOT / "backend/src/main/java/com/zentrip/api/"
            "OpenTripMapAttractionService.java"
        ).read_text())

    def test_cors_uses_exact_configured_origins_without_wildcard_default(self):
        properties = (
            ROOT / "backend/src/main/resources/application.properties"
        ).read_text()
        self.assertIn("api.setAllowedOrigins(exactOrigins)", WEB_CONFIG)
        self.assertIn("app.cors.allowed-origins=${CORS_ALLOWED_ORIGINS:}", properties)
        self.assertNotIn("allowedOriginPatterns", WEB_CONFIG)


if __name__ == "__main__":
    unittest.main()
