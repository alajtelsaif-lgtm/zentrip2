"""Tests use synthetic connection strings only, never workspace secrets."""
import runpy
import unittest
from pathlib import Path

backend_environment = runpy.run_path(
    str(Path(__file__).with_name("run-replit.py")), run_name="test_import"
)["backend_environment"]


class ConnectionSettingsTest(unittest.TestCase):
    def test_postgres_uri_moves_credentials_out_of_url(self):
        result = backend_environment({
            "SUPABASE_DB_URL": "postgresql://pool.user:p%40ss@db.example:6543/postgres"
        })
        self.assertEqual(result["SUPABASE_DB_USER"], "pool.user")
        self.assertEqual(result["SUPABASE_DB_PASSWORD"], "p@ss")
        self.assertEqual(
            result["SUPABASE_DB_URL"],
            "jdbc:postgresql://db.example:6543/postgres?sslmode=require",
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
        result = backend_environment({
            "SUPABASE_DB_URL": "jdbc:postgresql://db.example/postgres?user=test&password=example"
        })
        self.assertEqual(result["SUPABASE_DB_PASSWORD"], "example")
        self.assertNotIn("password", result["SUPABASE_DB_URL"])
        self.assertNotIn("user=", result["SUPABASE_DB_URL"])

    def test_missing_password_gives_actionable_error(self):
        with self.assertRaisesRegex(ValueError, "SUPABASE_DB_PASSWORD"):
            backend_environment({"SUPABASE_DB_URL": "postgres://db.example/postgres"})

    def test_invalid_connection_error_does_not_echo_input(self):
        with self.assertRaisesRegex(ValueError, "must be a PostgreSQL"):
            backend_environment({"SUPABASE_DB_URL": "not-a-url-with-sensitive-data"})


if __name__ == "__main__":
    unittest.main()
