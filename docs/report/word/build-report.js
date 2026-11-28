// Ghép báo cáo đồ án thành file Word từ các chương Markdown trong docs/report/ (thư viện docx).
// Chạy: NODE_PATH=<thư mục có node_modules/docx> node docs/report/word/build-report.js
// Nguồn nội dung là các file .md; sửa nội dung ở đó rồi chạy lại script, không sửa tay file .docx.
const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, ImageRun, PageBreak, Footer, Header, PageNumber,
  TableOfContents, ExternalHyperlink, LevelFormat, TabStopType, VerticalAlign, PageOrientation,
} = require("docx");

const REPORT = path.join(__dirname, "..");
const OUT = path.join(__dirname, "bao-cao-do-an.docx");
const FILES = [
  "chuong-1-tong-quan.md", "chuong-2-co-so-ly-thuyet.md", "chuong-3-phan-tich-thiet-ke.md",
  "chuong-4-trien-khai.md", "chuong-5-thuc-nghiem-danh-gia.md", "chuong-6-ket-luan.md",
  "tai-lieu-tham-khao.md", "phu-luc-a-huong-dan-dung-lai.md", "phu-luc-b-kich-ban-demo.md",
];

// ---------- Định dạng (A4, lề 3/2/2/2 cm, Times New Roman 13, giãn dòng 1,5) ----------
const FONT = "Times New Roman", MONO = "Courier New";
const cm = v => Math.round(v / 2.54 * 1440);
const CONTENT_W = cm(21 - 3 - 2); // 16 cm
const BODY = 26, SMALL = 22, CODE = 16;  // half-point
const LINE = 360;                        // 1,5 dòng
const NAVY = "0B3C49", TEAL = "0E7C7B", GRAY = "D0D7DE", TINT = "EEF4F5", CODEBG = "F3F5F7";

// ---------- Inline: **đậm**, *nghiêng*, `mã`, [chữ](url) ----------
function inline(text, base = {}) {
  const out = [];
  const re = /(`[^`]+`)|(\*\*[^*]+\*\*)|(\*[^*\s][^*]*\*)|(\[[^\]]+\]\([^)]+\))/g;
  let last = 0, m;
  const push = (t, o = {}) => { if (t) out.push(new TextRun({ text: t, font: FONT, ...base, ...o })); };
  while ((m = re.exec(text))) {
    push(text.slice(last, m.index));
    const tok = m[0];
    if (m[1]) out.push(new TextRun({ text: tok.slice(1, -1), font: MONO, size: Math.min(base.size || BODY, BODY) - 3, ...omit(base, ["size", "font"]) }));
    else if (m[2]) out.push(...inline(tok.slice(2, -2), { ...base, bold: true }));
    else if (m[3]) out.push(...inline(tok.slice(1, -1), { ...base, italics: true }));
    else {
      const [, label, url] = tok.match(/\[([^\]]+)\]\(([^)]+)\)/);
      if (/^https?:/.test(url)) out.push(new ExternalHyperlink({ link: url, children: [new TextRun({ text: label, font: FONT, color: TEAL, underline: {}, ...omit(base, ["color"]) })] }));
      else push(label, {});
    }
    last = re.lastIndex;
  }
  push(text.slice(last));
  // URL trần → liên kết
  return out.flatMap(r => r);
}
function omit(o, keys) { const c = { ...o }; keys.forEach(k => delete c[k]); return c; }
function linkify(text, base) {
  // liên kết Markdown [chữ](url) xử lý TRƯỚC, rồi mới tới URL trần và <url>; phần còn lại xử lý inline
  text = text.replace(/<(https?:\/\/[^>\s]+)>/g, "$1");
  const parts = text.split(/(\[[^\]]+\]\(https?:\/\/[^)\s]+\)|https?:\/\/[^\s)<>]+)/g);
  return parts.flatMap((p, i) => {
    if (!(i % 2)) return inline(p, base);
    const md = p.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/);
    const [label, url] = md ? [md[1], md[2]] : [p, p];
    return [new ExternalHyperlink({ link: url, children: [new TextRun({ text: label, font: FONT, color: TEAL, underline: {}, size: base.size })] })];
  });
}

// ---------- Khối ----------
const para = (children, o = {}) => new Paragraph({ children, spacing: { line: LINE, after: 120 }, alignment: AlignmentType.JUSTIFIED, ...o });
// đoạn có URL dài: căn trái (căn đều làm giãn khoảng trắng vì URL không ngắt được)
function bodyPara(text) { return para(linkify(text, { size: BODY }), /https?:\/\//.test(text) ? { alignment: AlignmentType.LEFT } : {}); }
function caption(text) {
  return new Paragraph({ children: inline(text, { size: SMALL, italics: true }), alignment: AlignmentType.CENTER, spacing: { before: 60, after: 200 }, keepLines: true });
}
function placeholder(text) {
  return new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 120, after: 200 },
    children: [new TextRun({ text, font: FONT, size: SMALL, italics: true, highlight: "yellow" })] });
}
function note(lines) {
  return lines.map((t, i) => new Paragraph({
    children: linkify(t, { size: BODY - 2 }), spacing: { line: 300, before: i ? 0 : 120, after: i === lines.length - 1 ? 200 : 60 },
    indent: { left: cm(0.6), right: cm(0.3) }, alignment: AlignmentType.JUSTIFIED,
    shading: { type: ShadingType.CLEAR, color: "auto", fill: TINT },
    border: { left: { style: BorderStyle.SINGLE, size: 18, color: TEAL, space: 8 } },
  }));
}
function codeBlock(lines) {
  return lines.map((l, i) => new Paragraph({
    children: [new TextRun({ text: l.length ? l : " ", font: MONO, size: CODE })],
    spacing: { line: 240, before: i ? 0 : 80, after: i === lines.length - 1 ? 200 : 0 },
    indent: { left: cm(0.3) }, keepLines: true, keepNext: i < lines.length - 1,
    shading: { type: ShadingType.CLEAR, color: "auto", fill: CODEBG },
  }));
}
function pngSize(file) { const b = fs.readFileSync(file); return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) }; }
function image(rel, alt) {
  const file = path.join(REPORT, rel.replace(/\.svg$/, ".png"));
  const { w, h } = pngSize(file);
  const width = 933; // 24,7 cm ở 96 dpi (trang nằm ngang)
  return new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 120, after: 60 }, keepNext: true,
    children: [new ImageRun({ type: "png", data: fs.readFileSync(file), transformation: { width, height: Math.round(width * h / w) },
      altText: { title: alt, description: alt, name: path.basename(file) } })] });
}
function splitRow(line) {
  const cells = []; let cur = "", code = false;
  const s = line.trim().replace(/^\|/, "").replace(/\|$/, "");
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === "`") code = !code;
    if (ch === "\\" && s[i + 1] === "|") { cur += "|"; i++; continue; }
    if (ch === "|" && !code) { cells.push(cur.trim()); cur = ""; continue; }
    cur += ch;
  }
  cells.push(cur.trim());
  return cells;
}
function table(lines) {
  const rows = lines.filter(l => !/^\|\s*:?-{2,}/.test(l.trim())).map(splitRow);
  const n = rows[0].length;
  const plain = t => t.replace(/[`*]/g, "").replace(/\[([^\]]+)\]\([^)]+\)/g, "$1");
  const weight = [...Array(n)].map((_, c) => Math.min(60, Math.max(6, ...rows.map(r => plain(r[c] || "").length))));
  const total = weight.reduce((a, b) => a + b, 0);
  const widths = weight.map(w => Math.floor(CONTENT_W * w / total));
  widths[n - 1] += CONTENT_W - widths.reduce((a, b) => a + b, 0);
  const border = { style: BorderStyle.SINGLE, size: 4, color: GRAY };
  return new Table({
    width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: widths,
    rows: rows.map((r, ri) => new TableRow({ tableHeader: ri === 0, cantSplit: true,
      children: widths.map((w, c) => new TableCell({
        width: { size: w, type: WidthType.DXA }, verticalAlign: VerticalAlign.CENTER,
        borders: { top: border, bottom: border, left: border, right: border },
        margins: { top: 50, bottom: 50, left: 90, right: 90 },
        shading: ri === 0 ? { type: ShadingType.CLEAR, color: "auto", fill: NAVY } : (ri % 2 === 0 ? { type: ShadingType.CLEAR, color: "auto", fill: TINT } : undefined),
        children: [new Paragraph({ spacing: { line: 260, before: 0, after: 0 },
          children: ri === 0 ? inline(r[c] || "", { size: SMALL, bold: true, color: "FFFFFF" }) : linkify(r[c] || "", { size: SMALL }) })],
      })) })),
  });
}

// ---------- Danh sách ----------
let listInstance = 0;
function listItem(kind, level, text) {
  const ref = kind === "num" ? "so" : "cham";
  return new Paragraph({ children: linkify(text, { size: BODY }), numbering: { reference: ref, level: Math.min(level, 2), instance: kind === "num" ? listInstance : 0 },
    spacing: { line: LINE, after: 40 }, alignment: AlignmentType.JUSTIFIED });
}

// ---------- Chuyển một file Markdown ----------
function convert(file) {
  const src = fs.readFileSync(path.join(REPORT, file), "utf8").replace(/\r/g, "").split("\n");
  const out = [];
  let i = 0, seenH1 = false, firstBlock = true, resumeList = false;
  const isList = l => /^\s*(- |\d+\. )/.test(l);
  while (i < src.length) {
    let line = src[i];
    if (!line.trim()) { i++; continue; }
    // Tiêu đề
    const h = line.match(/^(#{1,4}) (.*)$/);
    if (h) {
      resumeList = false;
      const lvl = h[1].length;
      let text = h[2].replace(/\s*\(bản nháp\)\s*$/i, "");
      if (lvl === 1) {
        out.push(new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: seenH1 || true, children: [new TextRun({ text: text.toUpperCase(), font: FONT })] }));
        seenH1 = true;
      } else {
        out.push(new Paragraph({ heading: [null, null, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3, HeadingLevel.HEADING_4][lvl], children: inline(text, {}) }));
      }
      i++; continue;
    }
    // Trích dẫn (blockquote)
    if (line.startsWith(">")) {
      const q = [];
      while (i < src.length && src[i].startsWith(">")) { q.push(src[i].replace(/^>\s?/, "")); i++; }
      const paras = q.join("\n").split(/\n\s*\n/).map(p => p.replace(/\n/g, " ").trim()).filter(Boolean);
      if (firstBlock && /^Bản nháp/.test(paras[0] || "")) { firstBlock = false; continue; } // ghi chú biên tập
      firstBlock = false;
      out.push(...note(paras));
      continue;
    }
    firstBlock = false;
    // Khối mã (có thể thụt lề trong danh sách)
    const fence = line.match(/^(\s*)```/);
    if (fence) {
      const ind = fence[1].length, code = [];
      i++;
      while (i < src.length && !/^\s*```/.test(src[i])) { code.push(src[i].slice(Math.min(ind, src[i].search(/\S|$/)))); i++; }
      i++;
      out.push(...codeBlock(code));
      continue;
    }
    // Bảng
    if (line.trim().startsWith("|")) {
      const t = [];
      while (i < src.length && src[i].trim().startsWith("|")) { t.push(src[i]); i++; }
      out.push(table(t));
      out.push(new Paragraph({ spacing: { after: 60 }, children: [] }));
      continue;
    }
    // Hình
    // Hình: đặt trên trang nằm ngang riêng, kèm chú thích ngay sau đó (nếu có)
    const img = line.match(/^!\[([^\]]*)\]\(([^)]+)\)/);
    if (img) {
      const kids = [image(img[2], img[1])];
      i++;
      while (i < src.length && !src[i].trim()) i++;
      if (i < src.length && /^\*(Hình|Bảng) \d/.test(src[i].trim())) { kids.push(caption(src[i].trim().replace(/^\*|\*$/g, ""))); i++; }
      out.push({ landscape: kids });
      continue;
    }
    // Chú thích hình/bảng và chỗ chờ ảnh chụp
    if (/^\*\(Hình [^)]*\)\*\s*$/.test(line.trim()) || /^\*\(Hình/.test(line.trim())) { out.push(placeholder(line.trim().replace(/^\*|\*$/g, "") + " — [CHÈN ẢNH CHỤP]")); i++; continue; }
    if (/^\*(Hình|Bảng) \d/.test(line.trim())) { out.push(caption(line.trim().replace(/^\*|\*$/g, ""))); i++; continue; }
    // Danh sách
    if (isList(line)) {
      const startNum = /^\s*\d+\. /.test(line);
      // danh sách đánh số bị khối mã chen giữa thì đánh số tiếp, không bắt đầu lại từ 1
      if (startNum && !(resumeList && /^\s*1\. /.test(line) === false)) listInstance++;
      resumeList = false;
      while (i < src.length && (isList(src[i]) || (src[i].trim() && /^\s{2,}\S/.test(src[i]) && !/^\s*```/.test(src[i])))) {
        const l = src[i];
        if (isList(l)) {
          const ind = l.search(/\S/), level = Math.floor(ind / 2);
          const num = /^\s*\d+\. /.test(l);
          let text = l.trim().replace(/^(- |\d+\. )/, "").replace(/^\[ \] /, "☐ ").replace(/^\[x\] /i, "☑ ");
          // dòng tiếp nối (thụt lề, không phải mục mới, không phải khối mã)
          while (i + 1 < src.length && src[i + 1].trim() && !isList(src[i + 1]) && /^\s{2,}\S/.test(src[i + 1]) && !/^\s*```/.test(src[i + 1])) { text += " " + src[i + 1].trim(); i++; }
          out.push(listItem(num ? "num" : "bullet", level, text));
        }
        i++;
        // khối mã thụt lề nằm trong mục danh sách: xử lý khối mã rồi quay lại danh sách
        if (i < src.length && /^\s+```/.test(src[i])) { resumeList = true; break; }
      }
      continue;
    }
    // Đoạn văn: gộp các dòng liền nhau
    resumeList = false;
    const p = [line.trim()];
    i++;
    while (i < src.length && src[i].trim() && !/^(#|>|\||!\[|\s*```|\s*- |\s*\d+\. )/.test(src[i])) { p.push(src[i].trim()); i++; }
    out.push(bodyPara(p.join(" ")));
  }
  return out;
}

// ---------- Trang bìa ----------
const hl = (t, o = {}) => new TextRun({ text: t, font: FONT, highlight: "yellow", ...o });
const tr = (t, o = {}) => new TextRun({ text: t, font: FONT, ...o });
const center = (children, o = {}) => new Paragraph({ alignment: AlignmentType.CENTER, children, ...o });
const cover = [
  center([hl("[TÊN TRƯỜNG]", { bold: true, size: 28 })], { spacing: { after: 60 } }),
  center([hl("[TÊN KHOA]", { bold: true, size: 28 })], { spacing: { after: 1400 } }),
  center([tr("BÁO CÁO ĐỒ ÁN", { bold: true, size: 40, color: NAVY })], { spacing: { after: 200 } }),
  center([tr("Môn: Công nghệ DevOps và Ứng dụng", { size: 28 })], { spacing: { after: 900 } }),
  center([tr("ĐỀ TÀI", { bold: true, size: 26 })], { spacing: { after: 120 } }),
  center([tr("XÂY DỰNG QUY TRÌNH BẢO MẬT CHUỖI CUNG ỨNG PHẦN MỀM CHO CONTAINER IMAGE SỬ DỤNG SBOM, AMAZON ECR MANAGED SIGNING VÀ KIỂM SOÁT TRIỂN KHAI TRÊN KUBERNETES",
    { bold: true, size: 32, color: NAVY })], { spacing: { line: 320, after: 1600 }, indent: { left: cm(0.5), right: cm(0.5) } }),
  ...[["Giảng viên hướng dẫn", "[Họ tên giảng viên]"], ["Sinh viên thực hiện", "[Họ tên — MSSV]"], ["Lớp", "[Mã lớp]"]].map(([k, v]) =>
    new Paragraph({ tabStops: [{ type: TabStopType.LEFT, position: cm(7.8) }], indent: { left: cm(2) }, spacing: { after: 120 },
      children: [tr(k + ":", { bold: true, size: 26 }), tr("\t"), hl(v, { size: 26 })] })),
  center([hl("[Thành phố], tháng [mm] năm 2026", { italics: true, size: 26 })], { spacing: { before: 1800 } }),
];

// ---------- Danh mục từ viết tắt ----------
const ABBR = [
  ["AWS", "Amazon Web Services"], ["CEL", "Common Expression Language — ngôn ngữ biểu thức dùng trong policy Kubernetes/Kyverno"],
  ["CI/CD", "Continuous Integration / Continuous Delivery — tích hợp và chuyển giao liên tục"], ["CVE", "Common Vulnerabilities and Exposures — mã định danh lỗ hổng"],
  ["DevSecOps", "Đưa kiểm soát bảo mật vào quy trình DevOps"], ["ECR", "Amazon Elastic Container Registry"],
  ["EKS", "Amazon Elastic Kubernetes Service"], ["IAM", "AWS Identity and Access Management"],
  ["IRSA", "IAM Roles for Service Accounts — cấp role AWS cho ServiceAccount trên EKS"], ["JWT", "JSON Web Token"],
  ["KMS", "AWS Key Management Service"], ["OCI", "Open Container Initiative — chuẩn image và registry"],
  ["OIDC", "OpenID Connect — xác thực liên kết, dùng cho GitHub Actions → AWS"], ["PR", "Pull request"],
  ["RBAC", "Role-Based Access Control — phân quyền theo vai trò trong Kubernetes"], ["SBOM", "Software Bill of Materials — danh mục thành phần phần mềm"],
  ["SHA-256", "Hàm băm dùng làm digest/checksum"], ["SLSA", "Supply-chain Levels for Software Artifacts"],
  ["SSDF", "Secure Software Development Framework (NIST SP 800-218)"], ["SSO", "Single Sign-On (IAM Identity Center)"],
  ["TC", "Test case — ca kiểm thử (TC01–TC10)"],
];
function abbrTable() {
  const w = [cm(3.2), CONTENT_W - cm(3.2)];
  const border = { style: BorderStyle.SINGLE, size: 4, color: GRAY };
  const row = (a, b, head) => new TableRow({ tableHeader: head, children: [a, b].map((t, k) => new TableCell({
    width: { size: w[k], type: WidthType.DXA }, borders: { top: border, bottom: border, left: border, right: border },
    margins: { top: 40, bottom: 40, left: 90, right: 90 },
    shading: head ? { type: ShadingType.CLEAR, color: "auto", fill: NAVY } : undefined,
    children: [new Paragraph({ children: [tr(t, { size: SMALL + 2, bold: head || k === 0, color: head ? "FFFFFF" : undefined })] })] })) });
  return new Table({ width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: w,
    rows: [row("Viết tắt", "Ý nghĩa", true), ...ABBR.map(([a, b]) => row(a, b, false))] });
}

// ---------- Tài liệu ----------
const body = FILES.flatMap(convert);
const PAGE = { size: { width: cm(21), height: cm(29.7) }, margin: { top: cm(2), bottom: cm(2), left: cm(3), right: cm(2) } };
const LAND = { size: { width: cm(21), height: cm(29.7), orientation: PageOrientation.LANDSCAPE }, margin: { top: cm(2), bottom: cm(2), left: cm(2.5), right: cm(2.5) } };
const header = () => ({ default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT,
  children: [tr("Bảo mật chuỗi cung ứng cho container image", { size: 18, italics: true, color: "5B6C7A" })] })] }) });
const footer = () => ({ default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
  children: [new TextRun({ font: FONT, size: 22, children: [PageNumber.CURRENT] })] })] }) });
// Tách nội dung: đoạn thường vào section dọc; mỗi hình lớn vào một section ngang riêng
const front = [
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 300 }, children: [tr("MỤC LỤC", { bold: true, size: 32, color: NAVY })] }),
  new TableOfContents("Mục lục", { hyperlink: true, headingStyleRange: "1-2" }),
  new Paragraph({ children: [new PageBreak()] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 300 }, children: [tr("DANH MỤC TỪ VIẾT TẮT", { bold: true, size: 32, color: NAVY })] }),
  abbrTable(),
];
const mainSections = [];
let cur = front, first = true;
const flush = () => {
  if (!cur.length) return;
  mainSections.push({ properties: { page: first ? { ...PAGE, pageNumbers: { start: 1 } } : PAGE }, headers: header(), footers: footer(), children: cur });
  first = false; cur = [];
};
for (const item of body) {
  if (item && item.landscape) {
    flush();
    mainSections.push({ properties: { page: LAND }, headers: header(), footers: footer(), children: item.landscape });
  } else cur.push(item);
}
flush();
const doc = new Document({
  creator: "Duy Phan", title: "Báo cáo đồ án — Bảo mật chuỗi cung ứng cho container image",
  description: "Đồ án môn Công nghệ DevOps và Ứng dụng",
  features: { updateFields: true },
  styles: {
    default: { document: { run: { font: FONT, size: BODY } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 32, bold: true, color: NAVY }, paragraph: { alignment: AlignmentType.CENTER, spacing: { before: 0, after: 360 }, keepNext: true, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 28, bold: true, color: NAVY }, paragraph: { spacing: { before: 300, after: 120 }, keepNext: true, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 26, bold: true, italics: true, color: NAVY }, paragraph: { spacing: { before: 200, after: 100 }, keepNext: true, outlineLevel: 2 } },
      { id: "Heading4", name: "Heading 4", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 26, italics: true }, paragraph: { spacing: { before: 160, after: 80 }, keepNext: true, outlineLevel: 3 } },
    ],
  },
  numbering: { config: [
    { reference: "cham", levels: [0, 1, 2].map(l => ({ level: l, format: LevelFormat.BULLET, text: ["•", "–", "◦"][l], alignment: AlignmentType.LEFT,
      style: { paragraph: { indent: { left: cm(0.9 + 0.7 * l), hanging: cm(0.5) } } } })) },
    { reference: "so", levels: [0, 1, 2].map(l => ({ level: l, format: [LevelFormat.DECIMAL, LevelFormat.LOWER_LETTER, LevelFormat.LOWER_ROMAN][l],
      text: `%${l + 1}.`, alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: cm(0.9 + 0.7 * l), hanging: cm(0.55) } } } })) },
  ] },
  sections: [
    { properties: { page: PAGE }, children: cover },
    ...mainSections,
  ],
});

Packer.toBuffer(doc).then(buf => { fs.writeFileSync(OUT, buf); console.log("Đã ghi:", OUT, buf.length, "byte"); });
