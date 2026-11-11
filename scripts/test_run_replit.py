"""Tests use synthetic connection strings only, never workspace secrets."""
import runpy
import unittest
import tempfile
from pathlib import Path
from urllib.parse import quote, urlencode, urlunsplit

launcher = runpy.run_path(
    str(Path(__file__).with_name("run-replit.py")), run_name="test_import"
)
backend_environment = launcher["backend_environment"]
provider_environment = launcher["provider_environment"]


def postgres_uri(user, password, host, port, database, scheme="postgresql"):
    authority = (
        f"{quote(user, safe='')}:{quote(password, safe='')}@{host}:{port}"
    )
    return urlunsplit((scheme, authority, f"/{database}", "", ""))


class ConnectionSettingsTest(unittest.TestCase):
    def test_postgres_uri_moves_credentials_out_of_url(self):
        username = "pool" + ".user"
        password = "fixture" + "@value"
        result = backend_environment({
            "SUPABASE_DB_URL": postgres_uri(
                username, password, "db.example", 6543, "postgres"
            )
        })
        self.assertEqual(result["SUPABASE_DB_USER"], username)
        self.assertEqual(result["SUPABASE_DB_PASSWORD"], password)
        self.assertEqual(
            result["SUPABASE_DB_URL"],
            "jdbc:postgresql://db.example:6543/postgres?sslmode=require&prepareThreshold=0",
        )
        self.assertEqual(result["APP_BOOTSTRAP_ENABLED"], "false")
        self.assertEqual(result["DB_SCHEMA_INIT"], "never")
        self.assertEqual(result["SERVER_PORT"], "5000")

    def test_jdbc_url_and_separate_credentials(self):
        result = backend_environment({
            "SUPABASE_DB_URL": "jdbc:postgresql://db.example:5432/postgres?sslmode=verify-full",
            "SUPABASE_DB_USER": "existing",
            "SUPABASE_DB_PASSWORD": "test-password",
        })
        self.assertEqual(result["SUPABASE_DB_USER"], "existing")
        self.assertIn("sslmode=verify-full", result["SUPABASE_DB_URL"])

    def test_query_credentials_are_not_left_in_url(self):
        query = urlencode({"user": "fixture-user", "password": "fixture-password"})
        result = backend_environment({
            "SUPABASE_DB_URL": "jdbc:postgresql://db.example/postgres?" + query
        })
        self.assertEqual(result["SUPABASE_DB_PASSWORD"], "fixture-password")
        self.assertNotIn("password", result["SUPABASE_DB_URL"])
        self.assertNotIn("user=", result["SUPABASE_DB_URL"])

    def test_missing_password_gives_actionable_error(self):
        with self.assertRaisesRegex(ValueError, "SUPABASE_DB_PASSWORD"):
            backend_environment({"SUPABASE_DB_URL": "postgres://db.example/postgres"})

    def test_invalid_connection_error_does_not_echo_input(self):
        with self.assertRaisesRegex(ValueError, "must be a PostgreSQL"):
            backend_environment({"SUPABASE_DB_URL": "not-a-url-with-sensitive-data"})

    def test_transaction_pooler_disables_url_prepared_statement_override(self):
        pooled_url = postgres_uri(
            "fixture-user", "fixture-password", "db.example", 6543, "postgres",
            scheme="postgres",
        ) + "?prepareThreshold=5"
        result = backend_environment({
            "SUPABASE_DB_URL": pooled_url
        })
        self.assertIn("prepareThreshold=0", result["SUPABASE_DB_URL"])
        self.assertNotIn("prepareThreshold=5", result["SUPABASE_DB_URL"])

    def test_provider_file_does_not_import_database_or_admin_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.env"
            path.write_text("GEMINI_API_KEY=example\nSUPABASE_DB_URL=other\n"
                            "APP_ADMIN_EMAIL=other@example.invalid\nDB_SCHEMA_INIT=always\n"
                            "SUPABASE_SERVICE_ROLE_KEY=not-for-this-process\n")
            result = provider_environment({"ZENTRIP_PROVIDER_ENV_FILE": str(path)})
        self.assertEqual(result["GEMINI_API_KEY"], "example")
        self.assertNotIn("SUPABASE_DB_URL", result)
        self.assertNotIn("APP_ADMIN_EMAIL", result)
        self.assertNotIn("DB_SCHEMA_INIT", result)
        self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", result)

    def test_existing_provider_secrets_take_precedence(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.env"
            path.write_text("GEMINI_API_KEY=file-example\n")
            result = provider_environment({
                "ZENTRIP_PROVIDER_ENV_FILE": str(path), "GEMINI_API_KEY": "environment-example"
            })
        self.assertEqual(result["GEMINI_API_KEY"], "environment-example")

    def test_provider_file_supports_quotes_comments_and_exports(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.env"
            path.write_text('export GEMINI_API_KEY="example#key" # comment\n'
                            "SERPAPI_KEY='another-example'\nGEMINI_MODEL=example-model # comment\n")
            result = provider_environment({"ZENTRIP_PROVIDER_ENV_FILE": str(path)})
        self.assertEqual(result["GEMINI_API_KEY"], "example#key")
        self.assertEqual(result["SERPAPI_KEY"], "another-example")
        self.assertEqual(result["GEMINI_MODEL"], "example-model")

    def test_invalid_provider_file_does_not_expose_its_contents(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.env"
            path.write_text('GEMINI_API_KEY="example-secret\n')
            with self.assertRaisesRegex(ValueError, "^A provider setting has invalid quoting.$"):
                provider_environment({"ZENTRIP_PROVIDER_ENV_FILE": str(path)})

    def test_no_provider_file_preserves_environment(self):
        self.assertEqual(provider_environment({"EXAMPLE": "test"}), {"EXAMPLE": "test"})


if __name__ == "__main__":
    unittest.main()
