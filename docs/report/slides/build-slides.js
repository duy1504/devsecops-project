// Dựng bộ slide bảo vệ từ docs/report/khung-slide.md (pptxgenjs, theme + layout + section).
// Chạy: NODE_PATH=<thư mục có node_modules/pptxgenjs> node docs/report/slides/build-slides.js
// Số liệu lấy từ Chương 5 / docs/test-results.md; hình từ docs/report/figures/*.png.
const path = require("path");
const pptxgen = require("pptxgenjs");
const { applyTheme } = require(process.env.PPTX_SKILL_DIR + "/scripts/apply_theme.js");

const FIG = path.join(__dirname, "..", "figures");
const OUT = path.join(__dirname, "bao-ve-chuoi-cung-ung.pptx");

const THEME = {
  name: "Chuoi cung ung",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "1B262C", lt1: "FFFFFF", dk2: "0B3C49", lt2: "EEF4F5",
    accent1: "0E7C7B", // xanh mòng két: kiểm soát, pipeline
    accent2: "E89B2F", // hổ phách: chữ ký, điểm nhấn
    accent3: "C8553D", // đỏ cam: bị chặn
    accent4: "2E8B57", // xanh lá: được nhận
    accent5: "5B6C7A", // xám đá: chữ phụ
    accent6: "9CC9CF", // xanh nhạt: chữ trên nền tối
    hlink: "0E7C7B", folHlink: "5B6C7A",
  },
};

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.333" x 7.5"
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
pres.title = "Bảo mật chuỗi cung ứng cho container image";
pres.subject = "Đồ án môn Công nghệ DevOps và Ứng dụng";
const C = pres.SchemeColor;
const S = pres.ShapeType;
const FOOT = "Bảo mật chuỗi cung ứng cho container image";

// ---------- Layout ----------
pres.defineSlideMaster({
  title: "NOI_DUNG",
  background: { color: C.background1 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.32, w: 9.3, h: 1.15,
      fontSize: 32, bold: true, color: C.text2, align: "left", valign: "middle", margin: 0 }, text: "" } },
    { text: { text: FOOT, options: { x: 0.6, y: 7.02, w: 8, h: 0.28, fontSize: 10, color: C.accent5, margin: 0 } } },
  ],
  slideNumber: { x: 12.25, y: 7.02, w: 0.5, h: 0.28, fontSize: 10, color: C.accent5, align: "right" },
});
pres.defineSlideMaster({
  title: "NOI_DUNG_TOI",
  background: { color: C.text2 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.32, w: 12.1, h: 1.15,
      fontSize: 32, bold: true, color: C.background1, align: "left", valign: "middle", margin: 0 }, text: "" } },
    { text: { text: FOOT, options: { x: 0.6, y: 7.02, w: 8, h: 0.28, fontSize: 10, color: C.accent6, margin: 0 } } },
  ],
  slideNumber: { x: 12.25, y: 7.02, w: 0.5, h: 0.28, fontSize: 10, color: C.accent6, align: "right" },
});
pres.defineSlideMaster({
  title: "TIEU_DE",
  background: { color: C.text2 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 1.55, w: 11.9, h: 1.7,
      fontSize: 40, bold: true, color: C.background1, align: "left", valign: "bottom", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 3.4, w: 11.7, h: 0.9,
      fontSize: 20, color: C.accent6, align: "left", valign: "top", margin: 0 }, text: "" } },
  ],
});

// ---------- Thành phần dùng lại ----------
const LINKS = ["Mã nguồn", "CI", "Registry", "Chữ ký", "Cụm"];
// Họa tiết: chuỗi 5 mắt xích ở góc phải, làm nổi mắt xích đang nói tới (active: mảng chỉ số)
function chain(slide, active) {
  const x0 = 10.15, y = 0.55, d = 0.34, step = 0.6;
  for (let i = 0; i < LINKS.length - 1; i++) {
    slide.addShape(S.line, { x: x0 + i * step + d, y: y + d / 2, w: step - d, h: 0,
      line: { color: C.accent5, width: 1.25 }, objectName: `chuoi-noi-${i + 1}` });
  }
  LINKS.forEach((t, i) => {
    const on = active.includes(i);
    slide.addShape(S.ellipse, { x: x0 + i * step, y, w: d, h: d, objectName: `chuoi-${i + 1}`,
      fill: { color: on ? C.accent2 : C.background2 }, line: { color: on ? C.accent2 : C.accent5, width: 1 } });
    slide.addText(t, { x: x0 + i * step - 0.18, y: y + d + 0.04, w: d + 0.36, h: 0.26, fontSize: 10,
      align: "center", color: on ? C.text2 : C.accent5, bold: on, margin: 0, isTextBox: true });
  });
}
function card(slide, x, y, w, h, fill, name) {
  slide.addShape(S.roundRect, { x, y, w, h, rectRadius: 0.08, fill: { color: fill || C.background2 },
    line: { color: fill || C.background2, width: 0.5 }, objectName: name });
}
function badge(slide, x, y, d, text, fill, color, size) {
  slide.addShape(S.ellipse, { x, y, w: d, h: d, fill: { color: fill }, line: { color: fill } });
  slide.addText(text, { x, y, w: d, h: d, fontSize: size || 14, bold: true, color: color || C.background1,
    align: "center", valign: "middle", margin: 0, isTextBox: true });
}
function arrow(slide, x, y, w, h, color) {
  slide.addShape(S.line, { x, y, w, h, line: { color: color || C.accent5, width: 1.75, endArrowType: "triangle" } });
}
function content(sectionTitle, title, active) {
  const s = pres.addSlide({ masterName: "NOI_DUNG", sectionTitle });
  s.addText(title, { placeholder: "title" });
  if (active) chain(s, active);
  return s;
}

// ================= Mở đầu =================
pres.addSection({ title: "Mở đầu" });
{
  const s = pres.addSlide({ masterName: "TIEU_DE", sectionTitle: "Mở đầu" });
  s.addText("Bảo mật chuỗi cung ứng cho container image", { placeholder: "title" });
  s.addText("SBOM · Amazon ECR Managed Signing · Kiểm soát triển khai trên Kubernetes", { placeholder: "body" });
  s.addText([
    { text: "Đồ án môn Công nghệ DevOps và Ứng dụng", options: { breakLine: true } },
    { text: "Sinh viên: [Họ tên — MSSV]     ·     Ngày bảo vệ: [dd/mm/yyyy]" },
  ], { x: 0.8, y: 4.55, w: 11.7, h: 0.8, fontSize: 16, color: C.background1, margin: 0, isTextBox: true });
  // chuỗi 5 mắt xích (lớn) làm hình chủ đề
  const x0 = 1.3, y = 5.75, d = 0.5, step = 2.2;
  for (let i = 0; i < 4; i++) s.addShape(S.line, { x: x0 + i * step + d, y: y + d / 2, w: step - d, h: 0, line: { color: C.accent6, width: 1.5 } });
  LINKS.forEach((t, i) => {
    s.addShape(S.ellipse, { x: x0 + i * step, y, w: d, h: d, fill: { color: i === 3 ? C.accent2 : C.text2 }, line: { color: i === 3 ? C.accent2 : C.accent6, width: 1.5 } });
    s.addText(t, { x: x0 + i * step + d / 2 - 0.8, y: y + d + 0.1, w: 1.6, h: 0.4, fontSize: 14, align: "center", color: i === 3 ? C.accent2 : C.accent6, margin: 0, isTextBox: true });
  });
  s.addNotes("Giới thiệu đề tài. Điền họ tên, MSSV, ngày bảo vệ trước khi trình chiếu. Chuỗi 5 mắt xích ở dưới sẽ xuất hiện ở góc mỗi slide để chỉ phần đang nói tới.");
}
{
  const s = content("Mở đầu", "Image “chạy được” chưa chắc đáng tin", [0, 1, 2, 3, 4]);
  const items = [
    ["2020", "SolarWinds", "Hệ thống build", "Mã độc chèn vào bản cập nhật hợp lệ, có chữ ký của nhà cung cấp"],
    ["2021", "Codecov", "Công cụ trong CI", "Script tải lên bị sửa để lấy secret của pipeline"],
    ["2024", "xz-utils", "Dependency mã nguồn mở", "Backdoor đưa vào thư viện nén qua người bảo trì"],
    ["2025", "tj-actions", "GitHub Action", "Tag bị trỏ sang commit độc hại, lộ secret trong log CI"],
  ];
  items.forEach(([yr, name, link, desc], i) => {
    const x = 0.6 + (i % 2) * 6.215, y = 1.75 + Math.floor(i / 2) * 2.45, w = 5.915, h = 2.2;
    card(s, x, y, w, h, C.background2, `su-co-${i + 1}`);
    s.addText(yr, { x: x + 0.3, y: y + 0.25, w: 1.3, h: 0.6, fontSize: 28, bold: true, color: C.accent1, margin: 0, isTextBox: true });
    s.addText(name, { x: x + 1.65, y: y + 0.25, w: w - 1.95, h: 0.6, fontSize: 22, bold: true, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
    s.addText(`Mắt xích: ${link}`, { x: x + 0.3, y: y + 0.95, w: w - 0.6, h: 0.4, fontSize: 16, bold: true, color: C.accent3, margin: 0, isTextBox: true });
    s.addText(desc, { x: x + 0.3, y: y + 1.38, w: w - 0.6, h: 0.65, fontSize: 15, color: C.text1, valign: "top", margin: 0, isTextBox: true });
  });
  s.addNotes("Bốn sự cố, mỗi sự cố đánh vào một mắt xích khác nhau. Kẻ tấn công không cần tấn công ứng dụng; chỉ cần một mắt xích. Kể cả 'có chữ ký' (SolarWinds) cũng chưa đủ.");
}
{
  const s = content("Mở đầu", "Hai lớp kiểm soát có chặn được không?", [0, 1, 2, 3, 4]);
  card(s, 0.6, 1.75, 5.5, 4.85, C.text2, "cau-hoi");
  s.addText("Câu hỏi nghiên cứu", { x: 0.95, y: 2.05, w: 4.8, h: 0.45, fontSize: 18, bold: true, color: C.accent2, margin: 0, isTextBox: true });
  s.addText("Phối hợp kiểm soát ở CI và ở Kubernetes admission có phát hiện hoặc ngăn được bốn tình huống, đồng thời truy vết được Pod → digest → SBOM → commit không?",
    { x: 0.95, y: 2.6, w: 4.8, h: 2.7, fontSize: 21, color: C.background1, valign: "top", margin: 0, isTextBox: true });
  s.addText("Phạm vi: 1 ứng dụng (podinfo) · 1 region AWS · cụm kind", { x: 0.95, y: 5.75, w: 4.8, h: 0.55, fontSize: 14, color: C.accent6, valign: "top", margin: 0, isTextBox: true });
  const t = [
    ["T1", "Secret trong mã nguồn", "Chặn ở CI: Gitleaks"],
    ["T2", "Image có CVE Critical", "Chặn ở CI: Trivy gate"],
    ["T3", "Image chưa ký / sai người ký", "Chặn ở admission: Policy 2"],
    ["T4", "Image từ nguồn không được phép", "Chặn ở admission: Policy 1"],
  ];
  t.forEach(([k, name, how], i) => {
    const x = 6.45 + (i % 2) * 3.19, y = 1.75 + Math.floor(i / 2) * 2.05, w = 3.0, h = 1.85;
    card(s, x, y, w, h, C.background2, `tinh-huong-${k}`);
    badge(s, x + 0.25, y + 0.25, 0.55, k, C.accent3, C.background1, 14);
    s.addText(name, { x: x + 0.95, y: y + 0.22, w: w - 1.15, h: 0.62, fontSize: 16, bold: true, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
    s.addText(how, { x: x + 0.25, y: y + 1.05, w: w - 0.45, h: 0.6, fontSize: 14, color: C.accent1, valign: "top", margin: 0, isTextBox: true });
  });
  s.addText("+ Yêu cầu thứ năm: truy vết hai chiều Pod ↔ commit",
    { x: 6.45, y: 5.95, w: 6.2, h: 0.6, fontSize: 15, italic: true, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
  s.addNotes("Câu hỏi nghiên cứu. Bốn tình huống của đề cương: hai cái chặn ở CI, hai cái chặn ở admission. Cộng thêm yêu cầu truy vết.");
}

// ================= Thiết kế =================
pres.addSection({ title: "Thiết kế" });
{
  const s = content("Thiết kế", "Hai lớp kiểm soát, nối bằng chữ ký số", [1, 3, 4]);
  s.addImage({ path: path.join(FIG, "hinh-3-1-kien-truc.png"), x: 0.6, y: 1.65, w: 12.13, h: 12.13 * 1200 / 2840,
    altText: "Kiến trúc: GitHub Actions (verify, publish), AWS (ECR, Signer), Kubernetes (Policy 1, Policy 2, Pod)" });
  s.addNotes("CI chặn trước khi PHÁT HÀNH, admission chặn trước khi CHẠY. Chữ ký do ECR Managed Signing tạo là cầu nối: admission không cần biết CI kiểm gì, chỉ cần biết image được ký bởi danh tính mà chỉ pipeline trên main dùng được. Lưu ý: ECR ký mọi image push vào repo, nên niềm tin dựa vào phân quyền push.");
}
{
  const s = content("Thiết kế", "Ba danh tính, mỗi danh tính một việc", [1, 2, 4]);
  s.addImage({ path: path.join(FIG, "hinh-4-1-xac-thuc.png"), x: 0.6, y: 1.95, w: 12.13, h: 12.13 * 940 / 2700,
    altText: "Ba đường xác thực: GitHub OIDC tới role publisher, extension tới role verifier, kubelet với imagePullSecret" });
  s.addNotes("Ba nhu cầu truy cập AWS, ba danh tính. Publisher chỉ push + ký, chỉ assume được từ nhánh main qua OIDC. Verifier chỉ đọc + kiểm thu hồi; trên kind credential sống tối đa 1 giờ. Kubelet chỉ kéo image.");
}

// ================= Triển khai =================
pres.addSection({ title: "Triển khai" });
{
  const s = content("Triển khai", "Build một lần, push đúng file đã quét", [1, 2]);
  s.addText("Job verify — không có quyền AWS · chạy cho mọi PR", { x: 0.6, y: 1.6, w: 12.1, h: 0.4, fontSize: 16, bold: true, color: C.accent5, margin: 0, isTextBox: true });
  const v = ["Unit test", "Gitleaks\ntoàn lịch sử", "Build 1 lần\n→ image.tar", "SBOM\nSyft, CycloneDX", "Trivy gate\n0 Critical"];
  const vw = (12.13 - 4 * 0.3) / 5;
  v.forEach((t, i) => {
    const x = 0.6 + i * (vw + 0.3);
    card(s, x, 2.05, vw, 1.1, C.background2, `verify-${i + 1}`);
    s.addText(t, { x, y: 2.05, w: vw, h: 1.1, fontSize: 16, bold: i === 4, color: i === 4 ? C.accent3 : C.text2, align: "center", valign: "middle", margin: 0, isTextBox: true });
    if (i < 4) arrow(s, x + vw + 0.04, 2.6, 0.22, 0);
  });
  arrow(s, 2.0, 3.2, 0, 0.6, C.accent1);
  s.addText("PASS + push vào main", { x: 2.15, y: 3.3, w: 3.5, h: 0.4, fontSize: 14, bold: true, color: C.accent1, margin: 0, isTextBox: true });
  s.addText("Job publish — OIDC, chỉ nhánh main", { x: 0.6, y: 3.9, w: 12.1, h: 0.4, fontSize: 16, bold: true, color: C.accent1, margin: 0, isTextBox: true });
  const p = ["Kiểm SHA-256\n+ image ID", "Push tag\nsha-<commit>-run-<id>", "Chờ ký COMPLETE\nđúng profile", "Ghi release.json"];
  const pw = (12.13 - 3 * 0.3) / 4;
  p.forEach((t, i) => {
    const x = 0.6 + i * (pw + 0.3);
    card(s, x, 4.35, pw, 1.1, C.accent1, `publish-${i + 1}`);
    s.addText(t, { x, y: 4.35, w: pw, h: 1.1, fontSize: 16, bold: true, color: C.background1, align: "center", valign: "middle", margin: 0, isTextBox: true });
    if (i < 3) arrow(s, x + pw + 0.04, 4.9, 0.22, 0);
  });
  s.addText([
    { text: "Không build lại: ", options: { bold: true } },
    { text: "image được push chính là image đã quét  ·  action ghim theo commit SHA  ·  main có branch protection" },
  ], { x: 0.6, y: 5.85, w: 12.13, h: 0.7, fontSize: 15, color: C.text2, valign: "middle", margin: 0, isTextBox: true });
  s.addNotes("verify không có quyền AWS, chạy cả cho PR. Gate chỉ nhìn đúng một kết quả quét (JSON) — quét một lần. publish chỉ chạy trên main sau khi verify đạt: tải đúng image.tar, kiểm SHA-256, verification.json và image ID rồi mới push. Thời gian: verify trung bình 105,5 s (n=35), publish 38,3 s (n=3).");
}
{
  const s = content("Triển khai", "Ký tự động khoảng 2 giây sau khi push", [2, 3]);
  card(s, 0.6, 1.75, 4.5, 4.85, C.text2, "chi-so-ky");
  s.addText("2,2 s", { x: 0.9, y: 2.25, w: 3.9, h: 1.3, fontSize: 72, bold: true, color: C.accent2, margin: 0, isTextBox: true });
  s.addText("trung bình từ lúc ECR nhận image tới khi có chữ ký", { x: 0.9, y: 3.65, w: 3.9, h: 0.9, fontSize: 17, color: C.background1, valign: "top", margin: 0, isTextBox: true });
  s.addText("n = 4 · 1,7–2,5 s · đo bằng mốc thời gian của chính ECR", { x: 0.9, y: 5.4, w: 3.9, h: 0.8, fontSize: 13, color: C.accent6, valign: "top", margin: 0, isTextBox: true });
  const rows = [
    ["1", "Ký tự động khi push", "ECR Managed Signing dùng AWS Signer; pipeline không có lệnh ký, không giữ khóa ký"],
    ["2", "Chỉ nhận đúng profile", "wait-signature.sh đòi COMPLETE của podinfo_signing_profile; FAILED hay hết giờ đều làm job fail"],
    ["3", "Chữ ký đi cùng digest", "Chữ ký Notation lưu trên ECR dạng OCI referrer, gắn vào digest, không sửa image"],
  ];
  rows.forEach(([n, h, d], i) => {
    const y = 1.85 + i * 1.6;
    badge(s, 5.5, y + 0.05, 0.6, n, C.accent2, C.text2, 18);
    s.addText(h, { x: 6.35, y, w: 6.35, h: 0.5, fontSize: 20, bold: true, color: C.text2, margin: 0, isTextBox: true });
    s.addText(d, { x: 6.35, y: y + 0.55, w: 6.35, h: 0.85, fontSize: 15, color: C.text1, valign: "top", margin: 0, isTextBox: true });
  });
  s.addNotes("ECR Managed Signing ký mọi image push vào repo khớp filter (đúng tên podinfo, không wildcard). Không đọc kết quả quét — 'chỉ image đạt mới được ký' là nhờ pipeline + quyền push. Publisher không cần signer:GetSigningProfile: đã bỏ thử và ký vẫn COMPLETE.");
}
{
  const s = content("Triển khai", "Hai policy admission, mặc định từ chối", [4]);
  const cols = [
    ["Policy 1 · Đúng nguồn", "ValidatingPolicy (CEL)", ["Chỉ <ECR>/podinfo@sha256:<64 hex>", "Kiểm cả init container", "Chặn TC05 sai nguồn · TC07 tag · TC08 init", "Đánh giá ngay trong Kyverno, ~200–300 ms"]],
    ["Policy 2 · Đúng người ký", "ClusterPolicy + extension", ["Chữ ký Notation của profile tin cậy (strict)", "Kiểm thu hồi qua AWS Signer", "Chặn TC04 chưa ký · TC06 sai người ký", "Gọi ECR + AWS Signer, +1,5–2 s mỗi Pod"]],
  ];
  cols.forEach(([h, sub, pts], i) => {
    const x = 0.6 + i * 6.215;
    card(s, x, 1.75, 5.915, 3.45, C.background2, `policy-${i + 1}`);
    s.addText(h, { x: x + 0.35, y: 1.95, w: 5.2, h: 0.55, fontSize: 22, bold: true, color: C.text2, margin: 0, isTextBox: true });
    s.addText(sub, { x: x + 0.35, y: 2.5, w: 5.2, h: 0.4, fontSize: 14, color: C.accent1, margin: 0, isTextBox: true });
    s.addText(pts.map((t, k) => ({ text: t, options: { bullet: true, breakLine: k < pts.length - 1 } })),
      { x: x + 0.35, y: 3.05, w: 5.3, h: 1.95, fontSize: 16, color: C.text1, paraSpaceAfter: 8, valign: "top", margin: 0, isTextBox: true });
  });
  const chips = [
    ["Fail-closed", "Verifier lỗi → Pod mới bị chặn sau ~0,3 s (TC09)", C.accent3],
    ["Extension tự build", "Bản phát hành có 6 Critical → tự build 0 Critical; vá lỗi token Kyverno 1.19", C.accent2],
  ];
  chips.forEach(([h, d, col], i) => {
    const x = 0.6 + i * 6.215;
    card(s, x, 5.45, 5.915, 1.2, C.background2, `chip-${i + 1}`);
    badge(s, x + 0.3, 5.75, 0.6, "!", col, C.background1, 20);
    s.addText(h, { x: x + 1.15, y: 5.55, w: 4.55, h: 0.42, fontSize: 17, bold: true, color: C.text2, margin: 0, isTextBox: true });
    s.addText(d, { x: x + 1.15, y: 5.97, w: 4.6, h: 0.6, fontSize: 14, color: C.text1, valign: "top", margin: 0, isTextBox: true });
  });
  s.addNotes("Tách hai policy để mỗi lần từ chối chỉ ra đúng một nguyên nhân. Policy 1 nhanh, không phụ thuộc dịch vụ ngoài. Policy 2 xác minh mọi image (imageReferences *), nên TC05/TC08 bị cả hai lớp chặn. Chỉ áp cho namespace app, demo. failurePolicy Fail cho cả hai.");
}

// ================= Demo =================
pres.addSection({ title: "Demo" });
{
  const s = pres.addSlide({ masterName: "NOI_DUNG_TOI", sectionTitle: "Demo" });
  s.addText("Demo trực tiếp", { placeholder: "title" });
  const steps = [
    ["Run thành công trên main", "SBOM, báo cáo, chữ ký trên ECR, release.json", "3 phút"],
    ["bash scripts/demo.sh tc01", "Pod chạy đúng digest phát hành, /version", "2 phút"],
    ["TC02, TC03 (run đã chạy)", "Gitleaks chặn secret giả · Trivy gate chặn 4 Critical", "1,5 phút"],
    ["bash scripts/demo.sh tc04 · tc05", "Chưa ký → Policy 2 chặn · sai nguồn → Policy 1 chặn", "3 phút"],
    ["bash scripts/demo.sh trace", "Pod → digest → tag ECR → chữ ký → run, commit", "2 phút"],
  ];
  steps.forEach(([h, d, t], i) => {
    const y = 1.75 + i * 0.98;
    badge(s, 0.6, y + 0.08, 0.62, String(i + 1), C.accent2, C.text2, 20);
    s.addText(h, { x: 1.5, y, w: 6.2, h: 0.45, fontSize: 19, bold: true, color: C.background1, margin: 0, isTextBox: true,
      fontFace: h.startsWith("bash") ? "Courier New" : undefined });
    s.addText(d, { x: 1.5, y: y + 0.45, w: 9.2, h: 0.38, fontSize: 15, color: C.accent6, margin: 0, isTextBox: true });
    s.addText(t, { x: 10.9, y: y + 0.08, w: 1.83, h: 0.5, fontSize: 15, color: C.accent6, align: "right", margin: 0, isTextBox: true });
  });
  s.addNotes("Chuyển sang trình duyệt và terminal theo Phụ lục B (4:30–13:00). Trước demo: refresh-lab-credentials.sh sát giờ, demo.sh check. TC09 không chạy trực tiếp (sẽ chặn mọi Pod) — mở slide dự phòng nếu được hỏi.");
}

// ================= Kết quả =================
pres.addSection({ title: "Kết quả" });
{
  const s = content("Kết quả", "10/10 ca chặn đúng lớp, đúng lý do", [0, 1, 2, 3, 4]);
  const MONO = new Set([3, 4, 5]); // TC04–TC06: trích nguyên văn thông báo từ chối
  const head = ["Ca", "Tình huống", "Lớp chặn", "Kết quả"].map(t => ({ text: t, options: { bold: true, color: C.background1, fill: { color: C.text2 } } }));
  const rows = [
    ["TC01", "Luồng hợp lệ, commit → Pod", "(được nhận)", "2 Pod chạy đúng digest"],
    ["TC02", "Secret giả trong mã", "Gitleaks (CI)", "verify fail, PR bị khóa"],
    ["TC03", "Image có CVE Critical", "Trivy gate (CI)", "4 Critical, không phát hành"],
    ["TC04", "Image chưa ký", "Policy 2", "no signature is associated"],
    ["TC05", "Image sai nguồn", "Policy 1", "Policy allowed-image failed"],
    ["TC06", "Ký bởi danh tính khác", "Policy 2 (danh tính)", "publisher doesn't match"],
    ["TC07", "Tag thay digest", "Policy 1", "Từ chối"],
    ["TC08", "Init container vi phạm", "Policy 1 + 2", "Từ chối"],
    ["TC09", "Verifier ngừng hoạt động", "Fail-closed", "Chặn sau ~0,3 s"],
    ["TC10", "Deployer vượt quyền", "RBAC", "6/6 Forbidden"],
  ].map((r, i) => r.map((t, k) => ({ text: t, options: {
    fill: { color: i % 2 ? C.background1 : C.background2 },
    color: k === 3 ? (i === 0 ? C.accent4 : C.accent3) : C.text1, bold: k === 0 || (k === 3 && !MONO.has(i)),
    fontFace: k === 3 && MONO.has(i) ? "Courier New" : undefined, fontSize: k === 3 && MONO.has(i) ? 13 : 14 } })));
  s.addTable([head, ...rows], { x: 0.6, y: 1.65, w: 12.13, colW: [1.0, 4.2, 3.0, 3.93], rowH: 0.41, fontSize: 14,
    valign: "middle", margin: [0, 0.12, 0, 0.12], border: { type: "solid", pt: 0.5, color: C.background2 } });
  s.addText("Mỗi lượt có đối chứng hợp lệ · bằng chứng: stderr + exit code + event + log (không dựa PolicyReport)",
    { x: 0.6, y: 6.35, w: 12.13, h: 0.45, fontSize: 14, italic: true, color: C.accent5, margin: 0, isTextBox: true });
  s.addNotes("Mỗi ca xác định trước lớp phải chặn và nguyên nhân; chỉ 'Đạt' khi chặn đúng lớp, đúng nguyên nhân. Policy 2 chạy 4 lượt, đều 6/6. Kết quả admission khớp xác minh độc lập bằng notation verify.");
}
{
  const s = content("Kết quả", "Chi phí bảo mật chỉ vài giây", [1, 3, 4]);
  const stats = [
    ["< 10 s", "để quét, trong job verify 105,5 s (n = 35)"],
    ["2,2 s", "chờ ký sau khi push (n = 4)"],
    ["+1,5–2 s", "xác minh chữ ký cho mỗi Pod hợp lệ"],
  ];
  stats.forEach(([v, d], i) => {
    const y = 1.75 + i * 1.65;
    card(s, 0.6, y, 4.4, 1.45, C.background2, `chi-phi-${i + 1}`);
    s.addText(v, { x: 0.85, y: y + 0.12, w: 3.9, h: 0.7, fontSize: 36, bold: true, color: C.accent1, margin: 0, isTextBox: true });
    s.addText(d, { x: 0.85, y: y + 0.82, w: 3.95, h: 0.55, fontSize: 14, color: C.text1, valign: "top", margin: 0, isTextBox: true });
  });
  s.addChart(pres.ChartType.bar, [{
    name: "Độ trễ trung bình (ms)",
    labels: ["Ngoài phạm vi (mốc)", "Chỉ Policy 1 (TC05/07/08)", "Extension tắt (TC09)", "Chưa ký (TC04)", "Sai người ký (TC06)", "Hợp lệ (TC01)"],
    values: [195, 232, 291, 765, 1166, 1854],
  }], {
    x: 5.35, y: 1.75, w: 7.38, h: 4.85, barDir: "bar",
    showTitle: true, title: "Độ trễ admission trung bình (ms, lệnh kubectl trên kind)", titleFontSize: 14, titleColor: C.text2, titleFontFace: "+mn-lt",
    chartColors: [THEME.colors.accent1], showLegend: false,
    showValue: true, dataLabelPosition: "outEnd", dataLabelFormatCode: "0", dataLabelFontSize: 13, dataLabelColor: C.text1, dataLabelFontFace: "+mn-lt",
    catAxisLabelFontSize: 13, catAxisLabelColor: C.text1, catAxisLabelFontFace: "+mn-lt",
    valAxisHidden: true, valGridLine: { style: "none" }, catGridLine: { style: "none" },
    catAxisLineShow: false, valAxisMaxVal: 2200,
  });
  s.addNotes("Số liệu Chương 5. Policy 1 (CEL) gần như không thêm độ trễ so với mốc. Policy 2 thêm 1,5–2 s cho Pod hợp lệ vì gọi ECR + AWS Signer, cache đang tắt. Khi extension tắt, Pod bị chặn ngay (~0,3 s), không chờ timeout 30 s.");
}
{
  const s = content("Kết quả", "Truy vết hai chiều từ Pod về commit", [0, 1, 2, 3, 4]);
  s.addImage({ path: path.join(FIG, "hinh-3-2-truy-vet.png"), x: 0.6, y: 1.65, w: 12.13, h: 12.13 * 760 / 2700,
    altText: "Chuỗi truy vết: commit, run, artifact, image trên ECR, chữ ký, Pod; release.json ghi các liên kết" });
  card(s, 0.6, 5.3, 12.13, 1.3, C.text2, "lenh-trace");
  s.addText("bash scripts/demo.sh trace", { x: 0.9, y: 5.42, w: 6, h: 0.45, fontSize: 18, bold: true, color: C.accent2, fontFace: "Courier New", margin: 0, isTextBox: true });
  s.addText("digest của Pod → tag sha-d1cd8dd72cd8-run-45798939183-1 → chữ ký COMPLETE → run, commit, SBOM",
    { x: 0.9, y: 5.9, w: 11.6, h: 0.6, fontSize: 15, color: C.background1, valign: "top", margin: 0, isTextBox: true });
  s.addNotes("Tag phát hành mang sẵn commit và run. release.json nối ba loại SHA: image ID local, SHA-256 của image.tar, digest trên ECR — không bằng nhau, nối bằng quy trình build một lần. Giới hạn: artifact GitHub giữ 30 ngày.");
}

// ================= Kết luận =================
pres.addSection({ title: "Kết luận" });
{
  const s = content("Kết luận", "Chạy thật mới lộ ra lỗi", [1, 4]);
  const items = [
    ["Extension không nhận token Kyverno 1.19", "Mọi Pod bị chặn. Vá TokenReview khai báo audience — không tắt bước xác thực"],
    ["Extension ghi bearer token vào log", "Bản vá chỉ ghi tên user; script thu bằng chứng lọc chuỗi JWT"],
    ["Claim OIDC thật khác mẫu tài liệu", "Repo dùng immutable subject (ID số); viết trust policy theo claim thật"],
    ["Repo public làm lộ account ID", "Account ID để ở Secret (log tự che); release.json thay bằng <ACCOUNT_ID>"],
  ];
  items.forEach(([h, d], i) => {
    const x = 0.6 + (i % 2) * 6.215, y = 1.75 + Math.floor(i / 2) * 2.45, w = 5.915, h2 = 2.2;
    card(s, x, y, w, h2, C.background2, `phat-hien-${i + 1}`);
    badge(s, x + 0.3, y + 0.3, 0.55, String(i + 1), C.accent3, C.background1, 16);
    s.addText(h, { x: x + 1.05, y: y + 0.25, w: w - 1.35, h: 0.75, fontSize: 18, bold: true, color: C.text2, valign: "top", margin: 0, isTextBox: true });
    s.addText("→ " + d, { x: x + 1.05, y: y + 1.05, w: w - 1.35, h: 1.0, fontSize: 15, color: C.text1, valign: "top", margin: 0, isTextBox: true });
  });
  s.addNotes("Bốn lỗi không thể thấy khi chỉ đọc tài liệu. Nguyên tắc: không 'chữa' bằng cách nới lỏng kiểm soát. Còn: extension bản phát hành 6 Critical; 'image ID' khác nghĩa tùy image store (Chương 4 mục 4.8).");
}
{
  const s = content("Kết luận", "Giới hạn cần nói rõ", [2, 3, 4]);
  const lim = [
    ["ECR ký mọi image push vào repo", "“Chỉ image đạt mới được ký” dựa vào pipeline và phân quyền push"],
    ["Chữ ký không chứng minh nội dung lành tính", "Pipeline hay role publisher bị chiếm vẫn ký được image độc hại"],
    ["SBOM và kết quả quét chưa được ký", "Admission chưa đòi được bằng chứng “image này đã qua quét”"],
    ["Admission chỉ kiểm yêu cầu mới", "Pod đang chạy không bị gỡ khi thu hồi chữ ký hay có CVE mới"],
  ];
  lim.forEach(([h, d], i) => {
    const y = 1.8 + i * 1.22;
    badge(s, 0.6, y + 0.12, 0.6, "!", C.accent3, C.background1, 20);
    s.addText(h, { x: 1.45, y, w: 6.2, h: 0.48, fontSize: 19, bold: true, color: C.text2, margin: 0, isTextBox: true });
    s.addText(d, { x: 1.45, y: y + 0.5, w: 6.2, h: 0.65, fontSize: 15, color: C.text1, valign: "top", margin: 0, isTextBox: true });
  });
  card(s, 8.0, 1.75, 4.73, 4.85, C.text2, "giam-thieu");
  s.addText("Đã giảm thiểu bằng", { x: 8.3, y: 2.0, w: 4.2, h: 0.5, fontSize: 19, bold: true, color: C.accent2, margin: 0, isTextBox: true });
  const mit = ["Chỉ role publisher push được (OIDC, chỉ main)", "Gate CI chạy trước khi push", "Branch protection, action ghim SHA", "Hướng phát triển: ký attestation kết quả quét"];
  s.addText(mit.map((t, k) => ({ text: t, options: { bullet: true, breakLine: k < mit.length - 1 } })),
    { x: 8.3, y: 2.65, w: 4.2, h: 3.7, fontSize: 16, color: C.background1, paraSpaceAfter: 12, valign: "top", margin: 0, isTextBox: true });
  s.addNotes("Nói thẳng giới hạn. Ngoài ra: môi trường kind một node, triển khai thủ công, credential verifier ≤ 1 giờ; ClusterPolicy deprecated; cỡ mẫu đo nhỏ.");
}
{
  const s = content("Kết luận", "Câu trả lời là có — và bước tiếp theo", [0, 1, 2, 3, 4]);
  card(s, 0.6, 1.75, 6.0, 4.85, C.text2, "ket-luan");
  s.addText("Trả lời câu hỏi nghiên cứu: CÓ", { x: 0.95, y: 2.0, w: 5.4, h: 0.55, fontSize: 22, bold: true, color: C.accent2, margin: 0, isTextBox: true });
  const conc = ["4/4 tình huống bị chặn đúng lớp", "Luồng hợp lệ đi trọn commit → Pod, không ký tay", "Truy vết hai chiều", "Chi phí: vài giây"];
  s.addText(conc.map((t, k) => ({ text: t, options: { bullet: true, breakLine: k < conc.length - 1 } })),
    { x: 0.95, y: 2.75, w: 5.4, h: 2.7, fontSize: 18, color: C.background1, paraSpaceAfter: 12, valign: "top", margin: 0, isTextBox: true });
  s.addText("TC01–TC10: 10/10 đạt · Policy 2 chạy 4 lượt, đều 6/6", { x: 0.95, y: 5.75, w: 5.4, h: 0.55, fontSize: 15, color: C.accent6, valign: "top", margin: 0, isTextBox: true });
  s.addText("Hướng phát triển", { x: 6.95, y: 1.8, w: 5.78, h: 0.5, fontSize: 22, bold: true, color: C.text2, margin: 0, isTextBox: true });
  const nxt = [
    ["Ký attestation kết quả quét", "và kiểm ở admission — niềm tin không còn chỉ dựa vào phân quyền"],
    ["EKS + IRSA, GitOps", "credential tự làm mới, triển khai tự động"],
    ["Quét lại định kỳ từ SBOM", "và xử lý Pod đang chạy khi thu hồi chữ ký"],
  ];
  nxt.forEach(([h, d], i) => {
    const y = 2.5 + i * 1.35;
    badge(s, 6.95, y + 0.05, 0.55, String(i + 1), C.accent1, C.background1, 16);
    s.addText(h, { x: 7.7, y, w: 5.03, h: 0.45, fontSize: 18, bold: true, color: C.text2, margin: 0, isTextBox: true });
    s.addText(d, { x: 7.7, y: y + 0.47, w: 5.03, h: 0.75, fontSize: 15, color: C.text1, valign: "top", margin: 0, isTextBox: true });
  });
  s.addNotes("Kết luận và hướng phát triển (Chương 6). Hướng 1 quan trọng nhất: biến giả định 'image có chữ ký là image đã qua quét' thành điều kiện được kiểm ở admission.");
}
{
  const s = pres.addSlide({ masterName: "TIEU_DE", sectionTitle: "Kết luận" });
  s.addText("Cảm ơn thầy cô và các bạn", { placeholder: "title" });
  s.addText("Hỏi đáp", { placeholder: "body" });
  s.addText([
    { text: "Mã nguồn, cấu hình, bằng chứng: ", options: { color: C.accent6 } },
    { text: "github.com/duy1504/devsecops-project", options: { bold: true, color: C.accent2, hyperlink: { url: "https://github.com/duy1504/devsecops-project" } } },
  ], { x: 0.8, y: 4.6, w: 11.7, h: 0.5, fontSize: 18, margin: 0, isTextBox: true });
  s.addText("Báo cáo: docs/report/  ·  Bằng chứng: docs/evidence/  ·  Kết quả: docs/test-results.md",
    { x: 0.8, y: 5.2, w: 11.7, h: 0.45, fontSize: 15, color: C.accent6, margin: 0, isTextBox: true });
  s.addNotes("Câu hỏi thường gặp và câu trả lời: Phụ lục B mục B.4. Các slide sau là dự phòng — chỉ mở khi được hỏi.");
}

// ================= Dự phòng =================
pres.addSection({ title: "Dự phòng" });
{
  const s = content("Dự phòng", "Dự phòng · Verifier lỗi thì Pod bị chặn ngay", [4]);
  card(s, 0.6, 1.75, 4.5, 4.85, C.text2, "tc09");
  s.addText("~0,3 s", { x: 0.9, y: 1.95, w: 3.9, h: 1.0, fontSize: 54, bold: true, color: C.accent3, margin: 0, isTextBox: true });
  s.addText("extension tắt → Pod hợp lệ bị từ chối, không chờ timeout 30 s", { x: 0.9, y: 2.95, w: 3.9, h: 0.9, fontSize: 16, color: C.background1, valign: "top", margin: 0, isTextBox: true });
  s.addText("~2,3 s", { x: 0.9, y: 4.15, w: 3.9, h: 1.0, fontSize: 54, bold: true, color: C.accent2, margin: 0, isTextBox: true });
  s.addText("bật lại → cùng Pod được nhận (trung bình 4 lượt)", { x: 0.9, y: 5.15, w: 3.9, h: 0.9, fontSize: 16, color: C.background1, valign: "top", margin: 0, isTextBox: true });
  const pts = [
    "4 lượt: 210, 405, 249, 298 ms — stderr “connection refused”",
    "Bật lại extension → cùng Pod được nhận (1607–2594 ms)",
    "failurePolicy: Fail cho cả hai policy; không đổi sang Ignore hay Audit",
    "Đánh đổi: tính sẵn sàng phụ thuộc verifier và credential (≤ 1 giờ trên kind; EKS dùng IRSA tự làm mới)",
  ];
  s.addText(pts.map((t, k) => ({ text: t, options: { bullet: true, breakLine: k < pts.length - 1 } })),
    { x: 5.5, y: 1.85, w: 7.23, h: 4.6, fontSize: 17, color: C.text1, paraSpaceAfter: 14, valign: "top", margin: 0, isTextBox: true });
  s.addNotes("TC09. Chạy trực tiếp nếu hội đồng muốn: scale extension về 0, demo.sh tc04 (bị chặn vì không kết nối được, không phải vì thiếu chữ ký), rồi scale lại 1.");
}
{
  const s = content("Dự phòng", "Dự phòng · Ma trận quyền", [1, 2, 4]);
  const hd = ["Danh tính", "Xác thực", "Được làm", "Không được"].map(t => ({ text: t, options: { bold: true, color: C.background1, fill: { color: C.text2 } } }));
  const rows = [
    ["devsecops-publisher", "GitHub OIDC, chỉ sub của main, phiên 900 s", "Push repo podinfo · SignPayload profile chính", "Sửa IAM, signing rule, xóa image"],
    ["devsecops-verifier", "AssumeRole từ SSO, ≤ 1 giờ", "Đọc ECR podinfo · GetRevocationStatus", "Push, ký (PutImage → AccessDenied)"],
    ["Deployer (Kubernetes)", "Role app-deployer, namespace app", "Tạo/sửa Deployment, Service · đọc Pod, log", "exec, Secret, ephemeral container, policy"],
    ["Quản trị lab", "SSO AdministratorAccess, 8 giờ", "Dựng hạ tầng (chỉ trên máy lab)", "Dùng trong CI"],
  ].map((r, i) => r.map((t, k) => ({ text: t, options: { fill: { color: i % 2 ? C.background1 : C.background2 }, bold: k === 0, color: k === 3 ? C.accent3 : C.text1 } })));
  s.addTable([hd, ...rows], { x: 0.6, y: 1.75, w: 12.13, colW: [2.6, 3.2, 3.33, 3.0], rowH: 0.9, fontSize: 14, valign: "middle",
    margin: [0, 0.12, 0, 0.12], border: { type: "solid", pt: 0.5, color: C.background2 } });
  s.addText("Mọi policy IAM kiểm bằng IAM Access Analyzer trước khi áp; không có access key dài hạn.",
    { x: 0.6, y: 6.35, w: 12.13, h: 0.45, fontSize: 14, italic: true, color: C.accent5, margin: 0, isTextBox: true });
  s.addNotes("Chi tiết: Chương 3 mục 3.5, Chương 4 mục 4.3.4.");
}
{
  const s = content("Dự phòng", "Dự phòng · Bộ phiên bản đã chốt", [0, 1, 4]);
  const hd = ["Thành phần", "Phiên bản", "Ghi chú"].map(t => ({ text: t, options: { bold: true, color: C.background1, fill: { color: C.text2 } } }));
  const rows = [
    ["Kyverno", "v1.19.2 (chart 3.9.2)", "Ghim; 1.20 đã ra nhưng extension dùng ClusterPolicy"],
    ["Kubernetes (kind)", "v1.35.8", "Node image ghim digest"],
    ["Trivy · Syft · Gitleaks", "0.76.2 · 1.56.0 · 8.30.1", "Binary ghim SHA-256"],
    ["Notation + plugin AWS Signer", "1.3.2 + 1.0.2292", "Root CA ghim fingerprint"],
    ["kyverno-notation-aws", "main@58b210b + bản vá p2", "Tự build, 0 Critical / 0 High"],
    ["configure-aws-credentials", "v6.3.0 (ghim commit SHA)", "Mọi action ghim SHA đầy đủ"],
  ].map((r, i) => r.map((t, k) => ({ text: t, options: { fill: { color: i % 2 ? C.background1 : C.background2 }, bold: k === 0, color: C.text1 } })));
  s.addTable([hd, ...rows], { x: 0.6, y: 1.75, w: 12.13, colW: [3.6, 3.6, 4.93], rowH: 0.6, fontSize: 15, valign: "middle",
    margin: [0, 0.12, 0, 0.12], border: { type: "solid", pt: 0.5, color: C.background2 } });
  s.addText("Kiểm lại bằng bash scripts/preflight.sh (33 mục, chỉ đọc) trước buổi bảo vệ.",
    { x: 0.6, y: 6.35, w: 12.13, h: 0.45, fontSize: 14, italic: true, color: C.accent5, margin: 0, isTextBox: true });
  s.addNotes("Đầy đủ kèm hash/digest: docs/versions.md.");
}
{
  const s = content("Dự phòng", "Dự phòng · Khó khăn và giải pháp", [1, 2, 4]);
  const hd = ["Vấn đề", "Giải pháp (không nới lỏng kiểm soát)"].map(t => ({ text: t, options: { bold: true, color: C.background1, fill: { color: C.text2 } } }));
  const rows = [
    ["Mọi Pod bị chặn: Token is not authorized", "Bản vá p2: TokenReview khai báo audience của Kyverno 1.19"],
    ["Extension ghi bearer token vào log", "Bản vá p2 chỉ ghi tên user; lọc JWT khi thu bằng chứng"],
    ["Extension bản phát hành có 6 Critical", "Tự build từ commit ghim, vá dependency, gate 0 Critical"],
    ["Trust OIDC theo mẫu luôn bị từ chối", "Lấy dạng sub thật (immutable subject) từ API GitHub"],
    ["Gitleaks làm fail PR không liên quan", "--log-opts=HEAD: chỉ quét lịch sử của commit đang kiểm"],
    ["So image ID của extension báo sai", "Docker 29 báo digest index, node báo config → so đúng loại"],
  ].map((r, i) => r.map((t, k) => ({ text: t, options: { fill: { color: i % 2 ? C.background1 : C.background2 }, bold: k === 0, color: C.text1 } })));
  s.addTable([hd, ...rows], { x: 0.6, y: 1.75, w: 12.13, colW: [5.2, 6.93], rowH: 0.65, fontSize: 15, valign: "middle",
    margin: [0, 0.12, 0, 0.12], border: { type: "solid", pt: 0.5, color: C.background2 } });
  s.addNotes("Đầy đủ 14 vấn đề: Chương 4 mục 4.8.");
}

(async () => {
  await pres.writeFile({ fileName: OUT });
  await applyTheme(OUT, THEME);
  console.log("Đã ghi:", OUT);
})().catch(e => { console.error(e); process.exit(1); });
