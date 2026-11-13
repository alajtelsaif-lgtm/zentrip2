#!/usr/bin/env node
"use strict";

/**
 * Read-only live Supabase schema export.
 * Produces an editable Word ER diagram (native Word drawing canvases,
 * shapes, connectors and tables) plus a complete column dictionary.
 */

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const {
  AlignmentType,
  BorderStyle,
  Document,
  HeadingLevel,
  PageBreak,
  PageOrientation,
  Paragraph,
  Packer,
  ShadingType,
  Table,
  TableCell,
  TableRow,
  TextRun,
  WidthType,
} = require("docx");
const { ShapeCanvasRun } = require("docx/shapes");

const ROOT = path.resolve(__dirname, "..");
const OUTPUT = path.join(ROOT, "generated-artifacts", "ZenTrip-Supabase-Database-Diagram.docx");
const COLORS = {
  ink: "24364B",
  muted: "5F7183",
  blue: "466B91",
  border: "C9D5E1",
  paper: "F5F8FB",
  white: "FFFFFF",
  account: { fill: "EEF4FB", line: "7997B7", accent: "315B85" },
  partner: { fill: "F3F0FA", line: "9284B7", accent: "65528B" },
  booking: { fill: "EEF6F5", line: "77A49D", accent: "39766D" },
  destination: { fill: "F4F6EA", line: "A1AA6E", accent: "69743A" },
  system: { fill: "F3F4F6", line: "9AA3AD", accent: "59636F" },
};

const SCHEMA_SQL = `
SELECT json_build_object(
  'database', current_database(),
  'schema', current_schema(),
  'serverVersion', current_setting('server_version'),
  'tables', (
    SELECT COALESCE(json_agg(
      json_build_object(
        'name', t.table_name,
        'columns', (
          SELECT COALESCE(json_agg(json_build_object(
            'name', c.column_name,
            'udt', c.udt_name,
            'nullable', c.is_nullable = 'YES',
            'default', c.column_default,
            'charLength', c.character_maximum_length,
            'precision', c.numeric_precision,
            'scale', c.numeric_scale
          ) ORDER BY c.ordinal_position), '[]'::json)
          FROM information_schema.columns c
          WHERE c.table_schema = t.table_schema AND c.table_name = t.table_name
        )
      ) ORDER BY t.table_name
    ), '[]'::json)
    FROM information_schema.tables t
    WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
  ),
  'constraints', (
    SELECT COALESCE(json_agg(json_build_object(
      'table', tc.table_name,
      'name', tc.constraint_name,
      'type', tc.constraint_type,
      'columns', (
        SELECT COALESCE(json_agg(k.column_name ORDER BY k.ordinal_position), '[]'::json)
        FROM information_schema.key_column_usage k
        WHERE k.constraint_schema = tc.constraint_schema
          AND k.constraint_name = tc.constraint_name
          AND k.table_name = tc.table_name
      )
    ) ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name), '[]'::json)
    FROM information_schema.table_constraints tc
    WHERE tc.table_schema = 'public' AND tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE')
  ),
  'foreignKeys', (
    SELECT COALESCE(json_agg(json_build_object(
      'table', child.relname,
      'name', pc.conname,
      'refTable', parent.relname,
      'pairs', (
        SELECT json_agg(json_build_object(
          'column', child_column.attname,
          'refColumn', parent_column.attname
        ) ORDER BY key_pair.ordinality)
        FROM unnest(pc.conkey, pc.confkey) WITH ORDINALITY
          AS key_pair(child_attnum, parent_attnum, ordinality)
        JOIN pg_attribute child_column
          ON child_column.attrelid = pc.conrelid AND child_column.attnum = key_pair.child_attnum
        JOIN pg_attribute parent_column
          ON parent_column.attrelid = pc.confrelid AND parent_column.attnum = key_pair.parent_attnum
      ),
      'updateRule', CASE pc.confupdtype
        WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT' WHEN 'c' THEN 'CASCADE'
        WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END,
      'deleteRule', CASE pc.confdeltype
        WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT' WHEN 'c' THEN 'CASCADE'
        WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END
    ) ORDER BY child.relname, pc.conname), '[]'::json)
    FROM pg_constraint pc
    JOIN pg_class child ON child.oid = pc.conrelid
    JOIN pg_namespace child_schema ON child_schema.oid = child.relnamespace
    JOIN pg_class parent ON parent.oid = pc.confrelid
    WHERE pc.contype = 'f' AND child_schema.nspname = 'public'
  )
)::text;
`;

function pgEnvironment() {
  const raw = process.env.SUPABASE_DB_URL;
  if (!raw) throw new Error("SUPABASE_DB_URL is not configured in Replit Secrets.");
  const url = new URL(raw.replace(/^jdbc:/, ""));
  if (!["postgres:", "postgresql:"].includes(url.protocol) || !url.hostname) {
    throw new Error("SUPABASE_DB_URL must be a PostgreSQL or JDBC PostgreSQL URL.");
  }
  const env = { ...process.env };
  env.PGHOST = url.hostname;
  env.PGPORT = url.port || "5432";
  env.PGUSER = process.env.SUPABASE_DB_USER
    || decodeURIComponent(url.username)
    || "postgres";
  env.PGPASSWORD = decodeURIComponent(url.password)
    || process.env.SUPABASE_DB_PASSWORD
    || "";
  env.PGDATABASE = decodeURIComponent(url.pathname.replace(/^\/+/, "")) || "postgres";
  env.PGSSLMODE = url.searchParams.get("sslmode") || "require";
  const channelBinding = url.searchParams.get("channelBinding")
    || url.searchParams.get("channel_binding");
  if (channelBinding) env.PGCHANNELBINDING = channelBinding;
  env.PGAPPNAME = "zentrip-schema-diagram-readonly";
  // Enforce read-only mode at the PostgreSQL session level, as well as using SELECT only.
  env.PGOPTIONS = "-c default_transaction_read_only=on";
  return env;
}

function readLiveSchema() {
  const env = pgEnvironment();
  let result;
  try {
    result = execFileSync(
      "psql",
      ["-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-P", "pager=off", "-c", SCHEMA_SQL],
      { cwd: ROOT, env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    ).trim();
  } catch (error) {
    if (error.code === "ENOENT") throw new Error("psql is required to read the Supabase schema.");
    const detail = String(error.stderr || "")
      .replace(/password authentication failed for user .+/gi, "password authentication failed for user [redacted]")
      .replace(/(user|host|database|dbname)=\S+/gi, "$1=[redacted]")
      .split(/\r?\n/)
      .filter(Boolean)
      .slice(-2)
      .join(" ");
    throw new Error(`Read-only Supabase schema query failed (psql exit ${error.status ?? "unknown"}). ${detail}`);
  }
  if (!result.startsWith("{")) {
    throw new Error("Supabase returned an unexpected schema metadata response.");
  }
  const schema = JSON.parse(result);
  schema.tables = schema.tables || [];
  schema.constraints = schema.constraints || [];
  schema.foreignKeys = schema.foreignKeys || [];
  if (!schema.tables.length) throw new Error("The public schema contains no base tables.");
  return schema;
}

function postgresType(column) {
  const simple = {
    int2: "smallint",
    int4: "integer",
    int8: "bigint",
    float4: "real",
    float8: "double precision",
    bpchar: "char",
    timestamptz: "timestamptz",
    timestamp: "timestamp",
    bool: "boolean",
  };
  if (column.udt === "varchar" && column.charLength) return `varchar(${column.charLength})`;
  if (column.udt === "numeric" && column.precision) {
    return `numeric(${column.precision},${column.scale || 0})`;
  }
  return simple[column.udt] || column.udt;
}

function prepareSchema(schema) {
  const constraints = new Map();
  for (const item of schema.constraints) {
    const key = `${item.table}:${item.type}`;
    if (!constraints.has(key)) constraints.set(key, []);
    constraints.get(key).push(item);
  }
  const foreignByTable = new Map();
  for (const fk of schema.foreignKeys) {
    if (!foreignByTable.has(fk.table)) foreignByTable.set(fk.table, []);
    foreignByTable.get(fk.table).push(fk);
  }
  for (const table of schema.tables) {
    table.primaryKeys = (constraints.get(`${table.name}:PRIMARY KEY`) || [])
      .flatMap((item) => item.columns);
    table.uniqueConstraints = constraints.get(`${table.name}:UNIQUE`) || [];
    table.foreignKeys = foreignByTable.get(table.name) || [];
    table.columns = table.columns.map((column) => {
      const keyFlags = [];
      if (table.primaryKeys.includes(column.name)) keyFlags.push("PK");
      for (const unique of table.uniqueConstraints) {
        if (unique.columns.length === 1 && unique.columns[0] === column.name) {
          keyFlags.push("UQ");
        } else if (unique.columns.length > 1 && unique.columns.includes(column.name)) {
          keyFlags.push(`UQ (${unique.columns.join(", ")})`);
        }
      }
      for (const fk of table.foreignKeys) {
        const pair = fk.pairs.find((entry) => entry.column === column.name);
        if (pair) keyFlags.push(`FK → ${fk.refTable}.${pair.refColumn}`);
      }
      return { ...column, displayType: postgresType(column), keyFlags };
    });
  }
  return schema;
}

function paragraph(text, options = {}) {
  const run = new TextRun({
    text: String(text ?? ""),
    font: "Arial",
    size: options.size || 19,
    bold: Boolean(options.bold),
    color: options.color || COLORS.ink,
  });
  return new Paragraph({
    heading: options.heading,
    alignment: options.alignment,
    spacing: { before: options.before || 0, after: options.after ?? 100 },
    keepNext: options.keepNext,
    children: [run],
  });
}

function cell(text, { header = false, width = 0 } = {}) {
  return new TableCell({
    width: width ? { size: width, type: WidthType.DXA } : undefined,
    shading: {
      fill: header ? "E8EEF4" : COLORS.white,
      type: ShadingType.CLEAR,
    },
    margins: { top: 55, bottom: 55, left: 90, right: 90 },
    borders: Object.fromEntries(["top", "bottom", "left", "right"].map((side) => [
      side,
      { style: BorderStyle.SINGLE, size: 3, color: COLORS.border },
    ])),
    children: [paragraph(text, {
      size: header ? 17 : 16,
      bold: header,
      color: header ? COLORS.ink : COLORS.muted,
      after: 0,
    })],
  });
}

function dataTable(rows, widths) {
  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    columnWidths: widths,
    rows: rows.map((row, index) => new TableRow({
      tableHeader: index === 0,
      children: row.map((value, column) => cell(value, {
        header: index === 0,
        width: widths[column],
      })),
    })),
  });
}

function keySummary(table) {
  const primary = table.primaryKeys.length ? table.primaryKeys.join(", ") : "none declared";
  const fks = table.foreignKeys.flatMap((fk) =>
    fk.pairs.map((pair) => `${pair.column} → ${fk.refTable}.${pair.refColumn}`));
  return { primary, fks };
}

function entityShape(table, id, x, y, palette) {
  const { primary, fks } = keySummary(table);
  const lines = [
    new Paragraph({
      spacing: { before: 0, after: 55 },
      children: [new TextRun({
        text: table.name,
        font: "Arial",
        size: 22,
        bold: true,
        color: palette.accent,
      })],
    }),
    new Paragraph({
      spacing: { before: 0, after: 35 },
      children: [new TextRun({
        text: `PK  ${primary}`,
        font: "Arial",
        size: 16,
        bold: true,
        color: COLORS.ink,
      })],
    }),
  ];
  const visibleFks = fks.slice(0, 3);
  for (const fk of visibleFks) {
    lines.push(new Paragraph({
      spacing: { before: 0, after: 20 },
      children: [new TextRun({ text: `FK  ${fk}`, font: "Arial", size: 13, color: COLORS.muted })],
    }));
  }
  if (fks.length > visibleFks.length) {
    lines.push(new Paragraph({
      spacing: { before: 0, after: 0 },
      children: [new TextRun({
        text: `+ ${fks.length - visibleFks.length} more FK`,
        font: "Arial",
        size: 13,
        color: COLORS.muted,
        italics: true,
      })],
    }));
  }
  return {
    id,
    type: "roundedRectangle",
    transformation: { offset: { left: x, top: y }, width: 285, height: 112 },
    fill: palette.fill,
    line: { color: palette.line, width: 1.2 },
    children: lines,
    textOptions: {
      verticalAlignment: "top",
      margins: { top: 6, right: 8, bottom: 4, left: 8 },
      wrap: true,
      shrinkTextOnOverflow: true,
    },
    altText: { title: table.name, description: `Supabase table ${table.name}, primary key ${primary}` },
  };
}

function externalShape(id, label, x, y, palette) {
  return {
    id,
    type: "roundedRectangle",
    transformation: { offset: { left: x, top: y }, width: 285, height: 82 },
    fill: "F8FAFC",
    line: { color: palette.line, width: 1.2, dash: "dash" },
    children: [
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 8, after: 0 },
        children: [new TextRun({ text: label, font: "Arial", size: 19, bold: true, color: palette.accent })],
      }),
    ],
    textOptions: { verticalAlignment: "center", margins: { top: 4, right: 6, bottom: 4, left: 6 } },
    altText: { title: label, description: "Shared entity; full fields are shown in another diagram page." },
  };
}

const PAGES = [
  {
    title: "Identity and user data",
    note: "User-owned data is connected through users.id. password_reset_codes is keyed by email and has no declared foreign key.",
    palette: COLORS.account,
    entries: [
      ["users", 337, 18],
      ["api_tokens", 20, 175],
      ["user_profiles", 337, 175],
      ["travel_preferences", 654, 175],
      ["ai_chat_messages", 20, 350],
      ["user_reviews", 337, 350],
      ["password_reset_codes", 654, 350],
    ],
  },
  {
    title: "Partner marketplace",
    note: "users.partner_id links optional staff/partner accounts to partners; each partner owns partner_listings.",
    palette: COLORS.partner,
    entries: [
      ["users", 20, 45],
      ["partners", 654, 45],
      ["partner_listings", 337, 300],
    ],
  },
  {
    title: "Trips, flights and bookings",
    note: "Solid connectors represent declared PostgreSQL foreign keys. A 1:N label means one referenced row may be linked by multiple child rows.",
    palette: COLORS.booking,
    entries: [
      ["users", 20, 18],
      ["partners", 337, 18],
      ["partner_listings", 654, 18],
      ["trips", 20, 300],
      ["bookings", 337, 300],
      ["flight_seat_holds", 654, 300],
    ],
  },
  {
    title: "Transfers",
    note: "transfer_schedules.transfer_id is both its primary key and a foreign key to transfers.id.",
    palette: COLORS.booking,
    entries: [
      ["users", 20, 18],
      ["partners", 337, 18],
      ["partner_listings", 654, 18],
      ["transfers", 337, 190],
      ["transfer_schedules", 337, 365],
    ],
  },
  {
    title: "Airports, offers and attractions",
    note: "No database foreign key is declared for airports or for the polymorphic user_reviews item_id; those references are application-level.",
    palette: COLORS.destination,
    entries: [
      ["airports", 20, 25],
      ["offers", 337, 25],
      ["offer_catalog_metadata", 654, 25],
      ["tourist_monuments", 337, 195],
      ["attraction_visit_counts", 20, 365],
      ["attraction_visit_dedup", 654, 365],
    ],
  },
];

function diagramPage(spec, schema, tablesByName, pageIndex) {
  const children = [];
  const included = new Set(spec.entries.map(([name]) => name));
  const ids = new Map();
  for (const [name, x, y] of spec.entries) {
    const table = tablesByName.get(name);
    if (!table) throw new Error(`Expected Supabase table is missing: ${name}`);
    const id = `p${pageIndex}_${name}`;
    ids.set(name, id);
    children.push(entityShape(table, id, x, y, spec.palette));
  }

  for (const fk of schema.foreignKeys) {
    if (!included.has(fk.table) || !included.has(fk.refTable)) continue;
    const oneToOne = fk.pairs.every((pair) => {
      const child = tablesByName.get(fk.table);
      return child.primaryKeys.includes(pair.column)
        || child.uniqueConstraints.some((constraint) => constraint.columns.length === 1
          && constraint.columns[0] === pair.column);
    });
    children.push({
      type: "connector",
      from: { id: ids.get(fk.refTable), side: "bottom" },
      to: { id: ids.get(fk.table), side: "top" },
      route: "elbow",
      line: { color: spec.palette.accent, width: 1.25, endArrow: "triangle" },
      label: { text: oneToOne ? "1:1" : "1:N", width: 42, height: 18, fill: "FFFFFF" },
      altText: {
        title: `${fk.refTable} to ${fk.table}`,
        description: `${fk.pairs.map((pair) => `${fk.refTable}.${pair.refColumn} → ${fk.table}.${pair.column}`).join("; ")}; ON DELETE ${fk.deleteRule}`,
      },
    });
  }

  return [
    new Paragraph({ children: [new PageBreak()] }),
    paragraph(spec.title, {
      heading: HeadingLevel.HEADING_1,
      size: 28,
      bold: true,
      color: spec.palette.accent,
      after: 60,
    }),
    paragraph("Editable Word ER diagram · live public-schema metadata", {
      size: 17,
      color: COLORS.muted,
      after: 65,
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { before: 0, after: 35 },
      children: [new ShapeCanvasRun({
        transformation: { width: 960, height: 500 },
        children,
        fill: COLORS.white,
        line: { color: "E1E7ED", width: 0.8 },
        fallback: true,
        altText: {
          title: `Supabase database diagram: ${spec.title}`,
          description: "Editable Word shapes and attached connectors for live Supabase tables.",
        },
      })],
    }),
    paragraph(spec.note, { size: 16, color: COLORS.muted, after: 35 }),
    paragraph("Diagram boxes and connectors are native Word drawing objects. Select a box to edit its text or move it; connectors stay attached.", {
      size: 15,
      color: COLORS.muted,
      after: 0,
    }),
  ];
}

function relationshipSection(schema) {
  const rows = [["Referenced table", "Referenced key", "Child table", "Foreign-key column(s)", "Delete rule"]];
  for (const fk of schema.foreignKeys) {
    rows.push([
      fk.refTable,
      fk.pairs.map((pair) => pair.refColumn).join(", "),
      fk.table,
      fk.pairs.map((pair) => pair.column).join(", "),
      fk.deleteRule,
    ]);
  }
  return [
    new Paragraph({ children: [new PageBreak()] }),
    paragraph("Foreign-key relationship register", {
      heading: HeadingLevel.HEADING_1,
      size: 28,
      bold: true,
      after: 75,
    }),
    paragraph("These are database-enforced relationships discovered in Supabase. Application-level identifiers without a PostgreSQL foreign-key constraint are not listed here.", {
      size: 17,
      color: COLORS.muted,
      after: 120,
    }),
    dataTable(rows, [2300, 2100, 2600, 3400, 3000]),
  ];
}

function dictionarySection(schema) {
  const content = [
    new Paragraph({ children: [new PageBreak()] }),
    paragraph("Live Supabase data dictionary", {
      heading: HeadingLevel.HEADING_1,
      size: 28,
      bold: true,
      after: 60,
    }),
    paragraph("Column names, PostgreSQL types, key constraints, nullability and defaults are read from information_schema. These Word tables are fully editable.", {
      size: 17,
      color: COLORS.muted,
      after: 120,
    }),
  ];
  for (const table of schema.tables) {
    content.push(paragraph(table.name, {
      heading: HeadingLevel.HEADING_2,
      size: 21,
      bold: true,
      color: COLORS.blue,
      before: 80,
      after: 45,
      keepNext: true,
    }));
    const rows = [["Column", "PostgreSQL type", "Key / relation", "Nullable", "Default"]];
    for (const column of table.columns) {
      rows.push([
        column.name,
        column.displayType,
        column.keyFlags.join("; ") || "—",
        column.nullable ? "Yes" : "No",
        column.default || "—",
      ]);
    }
    content.push(dataTable(rows, [2900, 2400, 4600, 1350, 4150]));
  }
  return content;
}

function buildDocument(schema) {
  const tablesByName = new Map(schema.tables.map((table) => [table.name, table]));
  const totalColumns = schema.tables.reduce((sum, table) => sum + table.columns.length, 0);
  const systemTable = tablesByName.get("flyway_schema_history");
  const snapshotDate = new Intl.DateTimeFormat("en-GB", {
    dateStyle: "long",
    timeZone: "UTC",
  }).format(new Date());
  const front = [
    paragraph("ZenTrip — Supabase Database Diagram", {
      heading: HeadingLevel.TITLE,
      alignment: AlignmentType.CENTER,
      size: 34,
      bold: true,
      after: 70,
    }),
    paragraph("Editable entity–relationship diagrams and live schema reference", {
      alignment: AlignmentType.CENTER,
      size: 20,
      color: COLORS.muted,
      after: 170,
    }),
    dataTable([
      ["Snapshot item", "Live Supabase result"],
      ["Database / schema", `${schema.database} / ${schema.schema}`],
      ["PostgreSQL version", schema.serverVersion],
      ["Public base tables", String(schema.tables.length)],
      ["Columns", String(totalColumns)],
      ["Declared foreign keys", String(schema.foreignKeys.length)],
      ["Read scope", "Catalog metadata only; no customer or booking rows read"],
      ["System table", systemTable ? "flyway_schema_history — migration history, no application foreign keys" : "Not present"],
      ["Snapshot date", snapshotDate],
    ], [4600, 10800]),
    paragraph("How to read the diagrams", {
      heading: HeadingLevel.HEADING_1,
      size: 25,
      bold: true,
      before: 170,
      after: 70,
    }),
    paragraph("Each entity is a native editable Word shape. PK marks the primary key; FK lines show the child-column reference; UQ denotes a unique constraint. Connectors point from a referenced table to the table that stores the foreign key. 1:1 appears when the child foreign-key column is unique; otherwise 1:N.", {
      size: 18,
      after: 100,
    }),
    paragraph("Only relationships enforced by PostgreSQL foreign keys are drawn. Some app-level links (such as user_reviews.item_id and password_reset_codes.email) are documented as notes, not presented as database-enforced links.", {
      size: 18,
      after: 0,
    }),
  ];

  const content = [...front];
  for (let i = 0; i < PAGES.length; i++) {
    content.push(...diagramPage(PAGES[i], schema, tablesByName, i + 1));
  }
  content.push(...relationshipSection(schema));
  content.push(...dictionarySection(schema));

  return new Document({
    creator: "Zentrip",
    title: "Zentrip Supabase Database Diagram",
    subject: "Live public-schema ERD and editable data dictionary",
    description: "Generated from read-only PostgreSQL catalog metadata in Supabase.",
    sections: [{
      properties: {
        page: {
          size: { width: 16838, height: 11906, orientation: PageOrientation.LANDSCAPE },
          margin: { top: 650, right: 720, bottom: 650, left: 720 },
        },
      },
      children: content,
    }],
  });
}

async function main() {
  const schema = prepareSchema(readLiveSchema());
  fs.mkdirSync(path.dirname(OUTPUT), { recursive: true });
  const buffer = await Packer.toBuffer(buildDocument(schema));
  fs.writeFileSync(OUTPUT, buffer);
  const columns = schema.tables.reduce((sum, table) => sum + table.columns.length, 0);
  console.log(`Created ${path.relative(ROOT, OUTPUT)} from Supabase public schema: `
    + `${schema.tables.length} tables, ${columns} columns, ${schema.foreignKeys.length} foreign keys.`);
}

main().catch((error) => {
  // Do not print database URLs, usernames, passwords, or raw connection errors.
  console.error(`Schema diagram generation failed: ${error.message}`);
  process.exitCode = 1;
});
