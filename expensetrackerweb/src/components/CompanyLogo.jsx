import { useRef, useState } from "react";
import { setCompanyLogo } from "../api.js";
import { useToast } from "../context/ToastContext.jsx";

// The company's logo, or its first letter when it has none.
export function CompanyAvatar({ company, size = 44, radius = 11, style }) {
  const box = { width: size, height: size, borderRadius: radius, flexShrink: 0, ...style };
  if (company?.logo) {
    // fills the whole tile (uploads are already trimmed to the logo itself)
    return <img src={company.logo} alt="" style={{ ...box, objectFit: "cover", background: "#fff", display: "block" }} />;
  }
  return (
    <div style={{ ...box, background: "#fff", color: "var(--forest)", display: "flex", alignItems: "center", justifyContent: "center", fontWeight: 700, fontSize: size * 0.39 }}>
      {company?.name?.[0]?.toUpperCase() || "C"}
    </div>
  );
}

// The part of the image that isn't plain border: rows/columns that only repeat the corner colour
// (white page margins, transparent padding) are cut off, so the logo itself fills the tile.
function contentBox(img) {
  const c = document.createElement("canvas");
  c.width = img.width;
  c.height = img.height;
  const ctx = c.getContext("2d");
  ctx.drawImage(img, 0, 0);
  const { data, width, height } = ctx.getImageData(0, 0, img.width, img.height);
  const at = (x, y) => (y * width + x) * 4;
  const bg = data.slice(0, 4); // top-left pixel = the border colour
  const isBorder = (i) =>
    (data[i + 3] < 16 && bg[3] < 16) || // both transparent
    (Math.abs(data[i] - bg[0]) + Math.abs(data[i + 1] - bg[1]) + Math.abs(data[i + 2] - bg[2]) < 36 && Math.abs(data[i + 3] - bg[3]) < 16);
  let top = 0, bottom = height - 1, left = 0, right = width - 1;
  const rowIsBorder = (y) => { for (let x = 0; x < width; x += 2) if (!isBorder(at(x, y))) return false; return true; };
  const colIsBorder = (x) => { for (let y = top; y <= bottom; y += 2) if (!isBorder(at(x, y))) return false; return true; };
  while (top < bottom && rowIsBorder(top)) top++;
  while (bottom > top && rowIsBorder(bottom)) bottom--;
  while (left < right && colIsBorder(left)) left++;
  while (right > left && colIsBorder(right)) right--;
  // nothing but border (a blank image): keep the whole thing
  if (right - left < 8 || bottom - top < 8) return { x: 0, y: 0, w: width, h: height };
  return { x: left, y: top, w: right - left + 1, h: bottom - top + 1 };
}

// Trim the border, then fill a 256px square (centre-cropped, like a profile photo), so the stored logo stays small.
function toLogoDataUrl(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const S = 256;
      const box = contentBox(img);
      const canvas = document.createElement("canvas");
      canvas.width = S;
      canvas.height = S;
      const ctx = canvas.getContext("2d");
      ctx.imageSmoothingQuality = "high";
      const ratio = box.w / box.h;
      if (ratio > 0.8 && ratio < 1.25) {
        // near-square: fill edge to edge (centre crop)
        const side = Math.min(box.w, box.h);
        ctx.drawImage(img, box.x + (box.w - side) / 2, box.y + (box.h - side) / 2, side, side, 0, 0, S, S);
      } else {
        // wide or tall (e.g. a wordmark): show all of it, as large as fits
        const scale = Math.min(S / box.w, S / box.h);
        const w = box.w * scale, h = box.h * scale;
        ctx.drawImage(img, box.x, box.y, box.w, box.h, (S - w) / 2, (S - h) / 2, w, h);
      }
      URL.revokeObjectURL(url);
      resolve(canvas.toDataURL("image/png"));
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("Could not read that image"));
    };
    img.src = url;
  });
}

// Settings card: upload, change or remove the logo (primary Admin only; the server checks too).
export function CompanyLogoCard({ company, user, onChanged }) {
  const { showToast } = useToast();
  const input = useRef(null);
  const [logo, setLogo] = useState(company.logo || "");
  const [saving, setSaving] = useState(false);

  async function save(next) {
    setSaving(true);
    const res = await setCompanyLogo(company._id, user.id, next);
    setSaving(false);
    if (!res.success) return showToast(res.message || "Could not update the logo", "error");
    setLogo(next);
    showToast(next ? "Logo updated" : "Logo removed");
    onChanged?.();
  }

  async function pick(e) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    if (!/^image\/(png|jpe?g|webp)$/.test(file.type)) return showToast("Choose a PNG, JPG or WebP image", "error");
    if (file.size > 5 * 1024 * 1024) return showToast("Image must be 5 MB or smaller", "error");
    try {
      save(await toLogoDataUrl(file));
    } catch (err) {
      showToast(err.message, "error");
    }
  }

  return (
    <div className="card" style={{ maxWidth: 560, marginBottom: 28, display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
      <CompanyAvatar company={{ ...company, logo }} size={64} radius={14} style={{ border: "1px solid var(--slate-border)" }} />
      <div style={{ flex: 1, minWidth: 180 }}>
        <h3 style={{ fontSize: 16, margin: "0 0 4px" }}>Company logo</h3>
        <p style={{ color: "var(--muted)", fontSize: 12.5, margin: 0 }}>Shown on the company tile for everyone in {company.name}. PNG, JPG or WebP; a square image works best.</p>
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <input ref={input} type="file" accept="image/png,image/jpeg,image/webp" onChange={pick} style={{ display: "none" }} />
        <button type="button" className="btn btn-primary" disabled={saving} onClick={() => input.current?.click()}>
          {saving ? "Saving…" : logo ? "Change" : "Upload logo"}
        </button>
        {logo && (
          <button type="button" className="btn btn-outline-danger" disabled={saving} onClick={() => save("")}>Remove</button>
        )}
      </div>
    </div>
  );
}
