const fs = require("node:fs");
const path = require("node:path");
const {
  AlignmentType,
  BorderStyle,
  Document,
  HeadingLevel,
  ImageRun,
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

const root = path.resolve(__dirname, "..");
const outputDir = path.join(root, "generated-artifacts");
const outputPath = path.join(outputDir, "ZenTrip-Activity-Diagram-Integrated.docx");
const pageSize = { width: 16838, height: 11906, orientation: PageOrientation.LANDSCAPE };

const diagrams = [
  ["01-access", "1 · Entry, Roles & App Navigation", "Roles come from the verified account; customers, admins, and partners enter separate app areas."],
  ["02-flight-search", "2 · Flight Search & Results", "Airport lookup selects the route; flight search merges partner inventory and Duffel offers."],
  ["03-flight-checkout", "3 · Flight Checkout (Provider-Specific)", "Partner flights use local seat holds; Duffel offers do not use the backend hold."],
  ["04-hotels", "4 · Hotel Search & Simulated Booking", "LiteAPI contributes hotel data; partner listings are also searched."],
  ["05-attractions", "5 · Places & Attraction Booking", "Place discovery and visit counting are separate from attraction booking."],
  ["06-other-bookings", "6 · Packages, Cars & Transfers", "Existing booking paths persist package, car, and transfer selections."],
  ["07-ai-trips", "7 · Zen AI, My Trips & Persistence", "Chat history is local and server-side; completed status is derived from trip dates."],
];

const flowSteps = [
  "Restore a saved session or authenticate. Read the verified role and route the account to customer, admin, or partner features.",
  "For a customer search, resolve airports or destination input, collect dates and travelers, and call the matching search endpoint.",
  "Normalize provider results and show partial-data warnings, empty states, or a retry path when providers fail.",
  "Select a flight, hotel, attraction, car, transfer, or package. Review details before proceeding.",
  "Run the applicable schedule-conflict check. Partner flights additionally reserve selected seats; Duffel flights do not use that hold.",
  "Run simulated checkout for paid products. Free attractions skip payment. No live supplier charge is made.",
  "On success, save through the existing trip, booking, or transfer endpoint. A Duffel flight is saved as a simulated trip, not a supplier ticket.",
  "Show current-user records in My Trips. Apply the existing cancellation behavior; derive completion from travel dates.",
];

const deviations = [
  "The actual project is Flutter with a Spring Boot backend, not Node/Express. The diagram generator and viewer are standalone tools and do not replace the app stack.",
  "The generic parallel flight/hotel/activity itinerary flow is not implemented. Customers book products through separate flows.",
  "Payment is simulated. The current flows do not issue flight tickets, charge a supplier, or make a live hotel reservation.",
  "LiteAPI is hotel search data only. The availability endpoint checks schedule conflicts, not a fresh provider room quote.",
  "No booking email/notification flow or server-side transfer-cancellation endpoint was found.",
  "No separate app-wide admin settings route was found. The diagram lists the current admin dashboard, partners, reservations, customers, places, and offers routes.",
];

const palette = {
  border: "D9E4DD",
  ink: "263A33",
  muted: "62756D",
  headFill: "EEF4EF",
  alternate: "F7FAF7",
};

function textParagraph(text, options = {}) {
  const runs = options.runs || [new TextRun({
    text,
    bold: options.bold,
    color: options.color || palette.ink,
    size: options.size || 21,
    font: "Arial",
  })];
  return new Paragraph({
    heading: options.heading,
    alignment: options.alignment,
    spacing: { before: options.before || 0, after: options.after ?? 120 },
    keepNext: options.keepNext,
    children: runs,
  });
}

function legendCell(text, fill) {
  return new TableCell({
    width: { size: 50, type: WidthType.PERCENTAGE },
    shading: { fill, type: ShadingType.CLEAR },
    margins: { top: 100, bottom: 100, left: 130, right: 130 },
    borders: {
      top: { style: BorderStyle.SINGLE, size: 4, color: palette.border },
      bottom: { style: BorderStyle.SINGLE, size: 4, color: palette.border },
      left: { style: BorderStyle.SINGLE, size: 4, color: palette.border },
      right: { style: BorderStyle.SINGLE, size: 4, color: palette.border },
    },
    children: [textParagraph(text, { after: 0, size: 19 })],
  });
}

function legendTable() {
  const rows = [
    ["Symbol", "Meaning"],
    ["● Start node", "Entry to the overall app flow."],
    ["◎ End node", "Exit from the overall flow (sign out)."],
    ["Rounded rectangle", "User or system action."],
    ["◇ Diamond", "Decision; each branch is labeled."],
    ["○ M", "Provider-result merge."],
    ["Solid arrow", "Normal action or API flow."],
    ["Dashed arrow", "Failure, retry, or documented limitation."],
    ["Fork / join bar", "Not used: the current booking paths are sequential, not parallel itinerary booking."],
  ];
  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    columnWidths: [4200, 8400],
    rows: rows.map((row, index) => new TableRow({
      children: row.map((cell) => legendCell(cell, index === 0 ? palette.headFill : palette.alternate)),
    })),
  });
}

function breakParagraph() {
  return new Paragraph({ children: [new PageBreak()] });
}

function diagramPage(diagram, index) {
  const [id, title, subtitle] = diagram;
  const imagePath = path.join(outputDir, `zentrip-activity-${id}-word.png`);
  if (!fs.existsSync(imagePath)) throw new Error(`Missing high-resolution diagram: ${imagePath}`);
  const imageData = fs.readFileSync(imagePath);
  const width = 1450;
  const height = Math.round(width * 1120 / 2200);
  const content = [];
  if (index === 0) {
    content.push(textParagraph("ZenTrip – Activity Diagram", {
      heading: HeadingLevel.TITLE,
      alignment: AlignmentType.CENTER,
      bold: true,
      size: 34,
      after: 90,
    }));
    content.push(textParagraph(
      "Current customer booking flows, role routing, dashboards, AI chat, and persistence.",
      { alignment: AlignmentType.CENTER, color: palette.muted, size: 19, after: 150 },
    ));
  } else {
    content.push(breakParagraph());
  }
  content.push(textParagraph(title, {
    heading: HeadingLevel.HEADING_1,
    bold: true,
    size: 27,
    after: 70,
  }));
  content.push(textParagraph(subtitle, { color: palette.muted, size: 18, after: 100 }));
  content.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 0, after: 90 },
    children: [new ImageRun({
      data: imageData,
      transformation: { width, height },
      altText: { title, description: subtitle, name: `ZenTrip activity diagram page ${index + 1}` },
    })],
  }));
  return content;
}

async function main() {
  fs.mkdirSync(outputDir, { recursive: true });
  const children = [];
  diagrams.forEach((diagram, index) => children.push(...diagramPage(diagram, index)));
  children.push(breakParagraph());
  children.push(textParagraph("Legend", { heading: HeadingLevel.HEADING_1, bold: true, size: 29 }));
  children.push(legendTable());
  children.push(breakParagraph());
  children.push(textParagraph("Numbered Flow Description", { heading: HeadingLevel.HEADING_1, bold: true, size: 29 }));
  flowSteps.forEach((step, index) => {
    children.push(textParagraph(`${index + 1}. ${step}`, { size: 20, after: 170 }));
  });
  children.push(breakParagraph());
  children.push(textParagraph("Deviations / Assumptions", { heading: HeadingLevel.HEADING_1, bold: true, size: 29 }));
  deviations.forEach((deviation) => {
    children.push(new Paragraph({
      bullet: { indent: 360 },
      spacing: { after: 130 },
      children: [new TextRun({ text: deviation, size: 20, font: "Arial", color: palette.ink })],
    }));
  });

  const document = new Document({
    creator: "ZenTrip",
    title: "ZenTrip – Activity Diagram",
    subject: "Verified activity flows for the existing application",
    description: "Seven diagrams, legend, numbered flow, and documented deviations.",
    styles: {
      default: {
        document: {
          run: { font: "Arial", size: 21, color: palette.ink },
          paragraph: { spacing: { after: 100 } },
        },
      },
    },
    sections: [{
      properties: {
        page: { size: pageSize, margin: { top: 520, right: 520, bottom: 520, left: 520 } },
      },
      children,
    }],
  });
  const buffer = await Packer.toBuffer(document);
  fs.writeFileSync(outputPath, buffer);
  console.log(`Generated ${path.relative(root, outputPath)} (${buffer.length} bytes)`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
