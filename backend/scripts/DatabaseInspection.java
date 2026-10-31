import java.sql.*;

/** Read-only, metadata-only inspection. Never prints credentials or application records. */
class DatabaseInspection {
    static void query(Connection connection, String section, String sql) throws SQLException {
        System.out.println("[" + section + "]");
        try (Statement statement = connection.createStatement()) {
            statement.setQueryTimeout(20);
            try (ResultSet rows = statement.executeQuery(sql)) {
                int columns = rows.getMetaData().getColumnCount();
                while (rows.next()) {
                    for (int i = 1; i <= columns; i++) {
                        if (i > 1) System.out.print("\t");
                        System.out.print(rows.getString(i));
                    }
                    System.out.println();
                }
            }
        }
    }

    public static void main(String[] args) {
        try (Connection connection = DriverManager.getConnection(
                System.getenv("SUPABASE_DB_URL"), System.getenv("SUPABASE_DB_USER"),
                System.getenv("SUPABASE_DB_PASSWORD"))) {
            connection.setReadOnly(true);
            connection.setAutoCommit(false);
            query(connection, "connection", """
                SELECT current_setting('server_version'), current_setting('transaction_read_only'),
                       current_schema()
                """);
            query(connection, "columns", """
                SELECT table_name, column_name, udt_name, is_nullable,
                       COALESCE(column_default, '')
                FROM information_schema.columns WHERE table_schema = 'public'
                ORDER BY table_name, ordinal_position
                """);
            query(connection, "constraints", """
                SELECT t.relname, c.conname, pg_get_constraintdef(c.oid)
                FROM pg_constraint c JOIN pg_class t ON c.conrelid = t.oid
                JOIN pg_namespace n ON t.relnamespace = n.oid
                WHERE n.nspname = 'public' ORDER BY t.relname, c.conname
                """);
            query(connection, "indexes", """
                SELECT tablename, indexname, indexdef FROM pg_indexes
                WHERE schemaname = 'public' ORDER BY tablename, indexname
                """);
            query(connection, "extensions", "SELECT extname FROM pg_extension ORDER BY extname");
            query(connection, "row-security", """
                SELECT relname, relrowsecurity, relforcerowsecurity
                FROM pg_class JOIN pg_namespace ON relnamespace = pg_namespace.oid
                WHERE nspname = 'public' AND relkind = 'r' ORDER BY relname
                """);
            query(connection, "inventory-health", """
                SELECT
                  COUNT(*) FILTER (WHERE available_rooms < 0) AS negative_rooms,
                  COUNT(*) FILTER (WHERE jsonb_typeof(attributes) <> 'object') AS non_object_attributes,
                  COUNT(*) FILTER (WHERE type = 'flight' AND attributes ? 'seats_available'
                    AND (attributes ->> 'seats_available') !~ '^[0-9]+$') AS invalid_flight_counts,
                  COUNT(*) FILTER (WHERE type = 'car' AND attributes ? 'available_vehicles'
                    AND (attributes ->> 'available_vehicles') !~ '^[0-9]+$') AS invalid_vehicle_counts
                FROM partner_listings
                """);
            query(connection, "schema-privileges", """
                SELECT has_schema_privilege(current_user, 'public', 'USAGE'),
                       bool_and(has_table_privilege(current_user, table_schema || '.' || table_name,
                                                    'SELECT,INSERT,UPDATE,DELETE'))
                FROM information_schema.tables
                WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
                """);
            query(connection, "invalid-constraints", """
                SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON c.connamespace = n.oid
                WHERE n.nspname = 'public' AND NOT c.convalidated
                """);
            System.out.println("[sequence-health]");
            try (Statement tables = connection.createStatement();
                 ResultSet records = tables.executeQuery("""
                    SELECT table_name FROM information_schema.columns
                    WHERE table_schema = 'public' AND column_name = 'id'
                      AND data_type = 'bigint' AND column_default LIKE 'nextval(%'
                    ORDER BY table_name
                    """)) {
                while (records.next()) {
                    String table = records.getString(1);
                    if (!table.matches("[a-z_]+")) throw new SQLException("Unsafe identifier", "XX000");
                    try (Statement sequence = connection.createStatement();
                         ResultSet state = sequence.executeQuery(
                            "SELECT COALESCE(MAX(id), 0), pg_sequence_last_value("
                            + "pg_get_serial_sequence('public." + table + "', 'id')::regclass) FROM public." + table)) {
                        state.next();
                        long maximum = state.getLong(1);
                        long last = state.getLong(2);
                        System.out.println(table + "\t" + (last >= maximum ? "ok" : "behind"));
                    }
                }
            }
            // Vault metadata may identify configured names, never secret contents.
            Savepoint vault = connection.setSavepoint();
            try {
                query(connection, "vault-key-names", "SELECT name FROM vault.secrets ORDER BY name LIMIT 50");
            } catch (SQLException exception) {
                connection.rollback(vault);
                System.out.println("Vault metadata unavailable; SQLSTATE=" + exception.getSQLState());
            }
            // Exercise the query beyond PG JDBC's default server-prepare threshold.
            try (PreparedStatement prepared = connection.prepareStatement(
                    "SELECT jsonb_set('{\"count\":2}'::jsonb, '{count}', to_jsonb(?::int)) ->> 'count'")) {
                for (int i = 0; i < 15; i++) {
                    prepared.setInt(1, i);
                    try (ResultSet result = prepared.executeQuery()) {
                        if (!result.next() || !Integer.toString(i).equals(result.getString(1))) {
                            throw new SQLException("Prepared query failed verification", "XX000");
                        }
                    }
                }
            }
            System.out.println("[prepared-queries]\n15 repeated PostgreSQL JSONB queries succeeded");
            connection.rollback();
        } catch (SQLException exception) {
            System.err.println("Inspection failed; SQLSTATE=" + exception.getSQLState()
                    + "; exception=" + exception.getClass().getSimpleName());
            System.exit(1);
        }
    }
}
