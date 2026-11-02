"""Development-only PostgreSQL administration; credentials never enter argv/logs."""

import argparse
import json
import uuid
from pathlib import Path
from urllib.parse import urlsplit

import certifi
import psycopg
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parents[1]
VERSION = "20261028000000"
MIGRATION = ROOT / f"supabase/migrations/{VERSION}_cloud_profiles.sql"


def connect():
    config = json.loads((ROOT / "config/supabase.development.json").read_text())
    if config.get("BUILDIFY_ENV") != "development":
        raise ValueError("Only the development environment is allowed.")
    origin = urlsplit(config["SUPABASE_URL"])
    if origin.scheme != "https" or not origin.hostname.endswith(".supabase.co"):
        raise ValueError("Expected the development Supabase project origin.")
    project_ref = origin.hostname.removesuffix(".supabase.co")
    settings = {}
    for line in (ROOT / ".env").read_text(encoding="utf-8-sig").splitlines():
        if line.strip() and not line.lstrip().startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            settings[key.strip()] = value
    password = settings.get("SUPABASE_DB_PASSWORD")
    if not password:
        raise ValueError("SUPABASE_DB_PASSWORD is required in the project's .env.")
    host = settings.get("SUPABASE_DB_HOST") or f"db.{origin.hostname}"
    user = settings.get("SUPABASE_DB_USER") or "postgres"
    direct = host == f"db.{origin.hostname}" and user == "postgres"
    pooled = host.endswith(".pooler.supabase.com") and user == f"postgres.{project_ref}"
    if not (direct or pooled):
        raise ValueError("The connection must target this project's direct or session-pooler endpoint.")
    port = int(settings.get("SUPABASE_DB_PORT") or "5432")
    if port != 5432:
        raise ValueError("Use the direct or session-pooler port 5432 for migrations.")
    connection = psycopg.connect(
        host=host, port=port, user=user, dbname="postgres", password=password,
        sslmode="verify-full", sslrootcert=settings.get("SUPABASE_DB_SSLROOTCERT") or certifi.where(),
        connect_timeout=10, application_name="buildify-development-migrations",
        options="-c statement_timeout=30000 -c lock_timeout=5000",
        autocommit=True,
    )
    print("Connected to development PostgreSQL with certificate/hostname verification.")
    return connection


def check(connection):
    row = connection.execute("select current_database(), current_user, to_regclass('public.profiles'), to_regclass('supabase_migrations.schema_migrations')").fetchone()
    if row[0] != "postgres" or row[1] != "postgres":
        raise ValueError("Unexpected administrative database/role.")
    print(f"Profiles table exists: {row[2] is not None}; migration ledger exists: {row[3] is not None}.")


def apply(connection):
    check(connection)
    migration = MIGRATION.read_text(encoding="utf-8")
    lines = migration.strip().splitlines()
    begin_index = next(i for i, line in enumerate(lines) if line.strip().lower() == "begin;")
    if any(line.strip() and not line.lstrip().startswith("--") for line in lines[:begin_index]) or lines[-1].strip().lower() != "commit;":
        raise ValueError("Expected the reviewed migration's outer transaction boundaries.")
    body = "\n".join(lines[begin_index + 1:-1])
    with connection.transaction():
        connection.execute("select pg_advisory_xact_lock(hashtext('buildify-development-migrations'))")
        ledger_exists = connection.execute("select to_regclass('supabase_migrations.schema_migrations')").fetchone()[0] is not None
        profile_exists = connection.execute("select to_regclass('public.profiles')").fetchone()[0] is not None
        if ledger_exists:
            applied = connection.execute("select version from supabase_migrations.schema_migrations where version = %s", (VERSION,)).fetchone()
            if applied:
                if not profile_exists:
                    raise ValueError("Recorded migration is missing its table; inspect database drift.")
                print("Migration already recorded; no DDL executed. Run verify to check access rules.")
                return
        if profile_exists:
            raise ValueError("An untracked profiles table exists. Review it before repairing migration history.")
        # The outer Python transaction makes DDL and history insertion atomic.
        connection.execute(body, prepare=False)
        # Metadata layout used by the Supabase CLI, not an application table.
        connection.execute("create schema if not exists supabase_migrations")
        connection.execute("create table if not exists supabase_migrations.schema_migrations (version text not null primary key)")
        connection.execute("alter table supabase_migrations.schema_migrations add column if not exists statements text[]")
        connection.execute("alter table supabase_migrations.schema_migrations add column if not exists name text")
        connection.execute("insert into supabase_migrations.schema_migrations (version, name, statements) values (%s, %s, %s)", (VERSION, "cloud_profiles", [body]))
        connection.execute("notify pgrst, 'reload schema'")
    print(f"Migration {VERSION} applied and recorded atomically; REST schema reload requested.")


def verify(connection):
    check(connection)
    if connection.execute("select relrowsecurity from pg_class where oid = 'public.profiles'::regclass").fetchone() != (True,):
        raise ValueError("Profile row-level security is not enabled.")
    with connection.transaction():
        owners = [uuid.uuid4(), uuid.uuid4()]
        for owner in owners:
            connection.execute(
                "insert into auth.users (id, email, raw_user_meta_data, aud, role) values (%s, %s, %s, 'authenticated', 'authenticated')",
                (owner, f"buildify-probe-{owner}@example.invalid", Jsonb({"display_name": "Buildify verification fixture"})),
            )
        if connection.execute("select count(*) from public.profiles where id = any(%s)", (owners,)).fetchone()[0] != 2:
            raise ValueError("The signup trigger did not create both profiles.")
        print("Signup trigger creates a profile for each synthetic identity.")
        connection.execute("set local role authenticated")
        connection.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({"sub": str(owners[0]), "role": "authenticated"}),))
        visible = connection.execute("select id from public.profiles").fetchall()
        if visible != [(owners[0],)]:
            raise ValueError("An owner can see rows outside their profile.")
        if connection.execute("update public.profiles set display_name = 'Updated fixture' where id = %s", (owners[0],)).rowcount != 1:
            raise ValueError("Owner display-name update failed.")
        if connection.execute("update public.profiles set display_name = 'Forbidden fixture' where id = %s", (owners[1],)).rowcount != 0:
            raise ValueError("Cross-account update was allowed.")
        print("Owner read/update works; other-account read/update is denied.")

        def denied(query, params=None):
            try:
                with connection.transaction():
                    connection.execute(query, params)
            except psycopg.errors.InsufficientPrivilege:
                return
            raise ValueError("A forbidden profile operation was accepted.")

        denied("delete from public.profiles where id = %s", (owners[0],))
        denied("insert into public.profiles (id, display_name) values (%s, 'Forbidden fixture')", (uuid.uuid4(),))
        denied("update public.profiles set id = %s where id = %s", (uuid.uuid4(), owners[0]))
        denied("update public.profiles set created_at = now() where id = %s", (owners[0],))
        denied("update public.profiles set updated_at = now() where id = %s", (owners[0],))
        print("Client insert/delete and identity/timestamp edits are denied.")
        connection.execute("reset role")
        connection.execute("set local role anon")
        connection.execute("select set_config('request.jwt.claims', '{}', true)")
        denied("select * from public.profiles")
        print("Anonymous profile access is denied.")
        # Every test fixture and display-name mutation is discarded, even on success.
        raise psycopg.Rollback()
    print("All isolation checks passed; synthetic identities and changes rolled back.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["check", "apply", "verify"])
    args = parser.parse_args()
    try:
        with connect() as connection:
            {"check": check, "apply": apply, "verify": verify}[args.command](connection)
    except Exception as error:
        # libpq errors may include connection metadata; never dump their raw text.
        print(f"Database operation failed: {type(error).__name__}; SQLSTATE={getattr(error, 'sqlstate', None)}.")
        detail = str(error).lower()
        categories = {
            "network/IPv6 unavailable": ("network is unreachable", "network unreachable", "10051", "10065", "no route"),
            "DNS resolution": ("could not translate host", "getaddrinfo", "name or service"),
            "certificate verification": ("certificate verify failed", "root certificate", "server certificate"),
            "authentication rejected": ("password authentication failed", "tenant or user not found"),
            "connection timeout/refused": ("timeout expired", "connection timed out", "connection refused", "10060", "10061"),
        }
        for label, markers in categories.items():
            if any(marker in detail for marker in markers):
                print(f"Failure category: {label}.")
        print("Check the project settings, password, IPv6 reachability, or session-pooler connection parameters. TLS verification remains enabled.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
