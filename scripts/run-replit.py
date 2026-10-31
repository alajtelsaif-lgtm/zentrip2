"""Run the existing backend and Flutter web build together, without logging secrets."""
import os
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlencode, urlsplit, urlunsplit

ROOT = Path(__file__).resolve().parent.parent


def backend_environment(source):
    env = dict(source)
    raw = env.get("SUPABASE_DB_URL") or env.get("DB_URL", "")
    if not raw:
        raise ValueError("Add SUPABASE_DB_URL in Replit Secrets before starting.")
    uri = raw.removeprefix("jdbc:")
    parsed = urlsplit(uri)
    if parsed.scheme not in ("postgres", "postgresql") or not parsed.hostname:
        raise ValueError("SUPABASE_DB_URL must be a PostgreSQL URI or JDBC URL.")
    options = dict(parse_qsl(parsed.query))
    username = (
        env.get("SUPABASE_DB_USER") or env.get("DB_USERNAME")
        or (unquote(parsed.username) if parsed.username else None)
        or options.pop("user", None) or "postgres"
    )
    password = (
        env.get("SUPABASE_DB_PASSWORD") or env.get("DB_PASSWORD")
        or (unquote(parsed.password) if parsed.password else None)
        or options.pop("password", None)
    )
    if not password:
        raise ValueError(
            "The database URL has no password. Add SUPABASE_DB_PASSWORD in Replit Secrets."
        )
    options.pop("user", None)
    options.pop("password", None)
    options.setdefault("sslmode", "require")
    host = parsed.hostname
    if ":" in host:
        host = f"[{host}]"
    if parsed.port:
        host += f":{parsed.port}"
    env["SUPABASE_DB_URL"] = "jdbc:" + urlunsplit(
        ("postgresql", host, parsed.path or "/postgres", urlencode(options), "")
    )
    env["SUPABASE_DB_USER"] = username
    env["SUPABASE_DB_PASSWORD"] = password
    env["SERVER_PORT"] = "5000"
    env["SERVER_ADDRESS"] = "0.0.0.0"
    # Imported databases must not have roles or schema rewritten on startup.
    env.setdefault("APP_BOOTSTRAP_ENABLED", "false")
    env.setdefault("DB_SCHEMA_INIT", "never")
    env["SPRING_WEB_RESOURCES_STATIC_LOCATIONS"] = (ROOT / "build/web").as_uri() + "/"
    return env


if __name__ == "__main__":
    try:
        environment = backend_environment(os.environ)
    except ValueError as exc:
        raise SystemExit(str(exc)) from None
    os.chdir(ROOT / "backend")
    java = ROOT / ".local/toolchains/jdk/bin/java"
    os.execve(str(java), [
        str(java), "-jar", "target/zentrip-api-1.0.0.jar",
    ], environment)
