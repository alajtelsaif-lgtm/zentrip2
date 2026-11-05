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
const manifest = JSON.parse(
  fs.readFileSync(path.join(outputDir, "zentrip-activity-manifest.json"), "utf8"),
);
const palette = {
  border: "D9E4DD",
  ink: "263A33",
  muted: "62756D",
  headFill: "EEF4EF",
  alternate: "F7FAF7",
};

function paragraph(text, options = {}) {
  return new Paragraph({
    heading: options.heading,
    alignment: options.alignment,
    spacing: { before: options.before || 0, after: options.after ?? 120 },
    keepNext: options.keepNext,
    children: [new TextRun({
      text,
      bold: options.bold,
      color: options.color || palette.ink,
      size: options.size || 21,
      font: "Arial",
    })],
  });
}

function bullet(text) {
  return new Paragraph({
    bullet: { indent: 360 },
    spacing: { after: 130 },
    children: [new TextRun({ text, size: 20, font: "Arial", color: palette.ink })],
  });
}

function cell(text, fill, bold = false) {
  return new TableCell({
    width: { size: 50, type: WidthType.PERCENTAGE },
    shading: { fill, type: ShadingType.CLEAR },
    margins: { top: 100, bottom: 100, left: 130, right: 130 },
    borders: Object.fromEntries(
      ["top", "bottom", "left", "right"].map((side) => [
        side,
        { style: BorderStyle.SINGLE, size: 4, color: palette.border },
      ]),
    ),
    children: [paragraph(text, { after: 0, size: 19, bold })],
  });
}

function legendTable() {
  const rows = [
    ["Symbol", "Meaning"],
    ["● Start", "The one entry to the full app flow."],
    ["◎ End", "The one sign-out end, reachable by Customer, Admin, and Partner."],
    ["Rounded rectangle", "User or system action."],
    ["◇ Diamond", "Decision; every outgoing branch is labeled."],
    ["○ M", "Merge of result or alternative paths."],
    ["┃ Fork / join bar", "Parallel provider lookups and My Trips source fetches; join waits for both branches."],
    ["○ Letter", "Off-page connector; the same letter appears on exactly two pages."],
    ["Solid arrow", "Normal flow."],
    ["Blue arrow", "API request or provider data."],
    ["Dashed red arrow", "Failure, retry, or documented limitation."],
  ];
  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    columnWidths: [4200, 8400],
    rows: rows.map((row, index) => new TableRow({
      children: row.map((value) =>
        cell(value, index === 0 ? palette.headFill : palette.alternate, index === 0),
      ),
    })),
  });
}

function diagramPage(page, index) {
  const imagePath = path.join(outputDir, page.image);
  if (!fs.existsSync(imagePath)) {
    throw new Error(`Missing 2× diagram image: ${imagePath}`);
  }
  const ratio = page.width / page.height;
  const width = Math.min(1040, Math.round(580 * ratio));
  const height = Math.round(width / ratio);
  const content = [];
  if (index === 0) {
    content.push(paragraph("ZenTrip – Verified Activity Diagram", {
      heading: HeadingLevel.TITLE,
      alignment: AlignmentType.CENTER,
      bold: true,
      size: 34,
      after: 70,
    }));
    content.push(paragraph(
      "Current Flutter and Spring Boot flows: role routing, travel products, checkout, AI, and trip persistence.",
      { alignment: AlignmentType.CENTER, color: palette.muted, size: 19, after: 150 },
    ));
  } else {
    content.push(new Paragraph({ children: [new PageBreak()] }));
  }
  content.push(paragraph(page.title, {
    heading: HeadingLevel.HEADING_1,
    bold: true,
    size: 27,
    after: 70,
  }));
  content.push(paragraph(page.subtitle, { color: palette.muted, size: 18, after: 90 }));
  content.push(new Paragraph({
    alignment: AlignmentType.CENTER,
    spacing: { before: 0, after: 80 },
    children: [new ImageRun({
      data: fs.readFileSync(imagePath),
      transformation: { width, height },
      altText: {
        title: page.title,
        description: page.subtitle,
        name: `ZenTrip activity diagram ${index}`,
      },
    })],
  }));
  content.push(paragraph(`Diagram note: ${page.note}`, {
    color: palette.muted,
    size: 17,
    after: 0,
  }));
  return content;
}

function sectionHeading(text) {
  return paragraph(text, {
    heading: HeadingLevel.HEADING_1,
    bold: true,
    size: 29,
    after: 180,
  });
}

async function main() {
  const children = [];
  manifest.pages.forEach((page, index) => children.push(...diagramPage(page, index)));

  children.push(new Paragraph({ children: [new PageBreak()] }));
  children.push(sectionHeading("Legend"));
  children.push(legendTable());

  children.push(new Paragraph({ children: [new PageBreak()] }));
  children.push(sectionHeading("Numbered End-to-End Flow"));
  manifest.flowSteps.forEach((step, index) => {
    children.push(paragraph(`${index + 1}. ${step}`, { size: 20, after: 170 }));
  });

  children.push(new Paragraph({ children: [new PageBreak()] }));
  children.push(sectionHeading("Fixes Applied"));
  manifest.fixes.forEach((fix) => children.push(bullet(fix)));

  children.push(new Paragraph({ children: [new PageBreak()] }));
  children.push(sectionHeading("Deviations / Assumptions"));
  manifest.deviations.forEach((deviation) => children.push(bullet(deviation)));

  const document = new Document({
    creator: "ZenTrip",
    title: "ZenTrip – Verified Activity Diagram",
    subject: "Verified activity flows for the existing application",
    description: "Master flow, seven connected detail diagrams, legend, flow, fixes, and deviations.",
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
        page: {
          size: { width: 16838, height: 11906, orientation: PageOrientation.LANDSCAPE },
          margin: { top: 420, right: 520, bottom: 420, left: 520 },
        },
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
