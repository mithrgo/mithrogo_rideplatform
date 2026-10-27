"use client";

import { FormEvent, useState } from "react";

import { Badge, ErrorBox, PageHead, Table } from "@/components/ui";
import { api, ApiError } from "@/lib/api";
import type { QuickPlace } from "@/lib/types";
import { useAction, useApi } from "@/lib/useApi";

const ICONS: [string, string][] = [
  ["place", "Pin"], ["train", "Train"], ["bus", "Bus"], ["mall", "Shopping"], ["hospital", "Hospital"],
  ["temple", "Temple"], ["school", "School"], ["airport", "Airport"], ["restaurant", "Food"], ["park", "Park"],
  ["office", "Office"],
];

const EMPTY = { name: "", address: "", latitude: "", longitude: "", icon: "place", sort_order: "0" };

export default function QuickPlacesPage() {
  const places = useApi<QuickPlace[]>("admin/quick-places/");
  const action = useAction();
  const [form, setForm] = useState(EMPTY);
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [open, setOpen] = useState(false);

  const set = (key: keyof typeof EMPTY, value: string) => setForm((f) => ({ ...f, [key]: value }));
  const err = (k: string) => fieldErrors[k] && <span className="field-error">{fieldErrors[k]}</span>;

  async function create(event: FormEvent) {
    event.preventDefault();
    setFieldErrors({});
    const created = await action.run(async () => {
      try {
        return await api<QuickPlace>("admin/quick-places/", {
          method: "POST",
          body: { ...form, sort_order: Number(form.sort_order) || 0 },
        });
      } catch (e) {
        if (e instanceof ApiError) setFieldErrors(e.fields);
        throw e;
      }
    });
    if (created) {
      setForm(EMPTY);
      setOpen(false);
      places.reload();
    }
  }

  async function patch(place: QuickPlace, body: Partial<QuickPlace>) {
    const done = await action.run(() => api(`admin/quick-places/${place.id}/`, { method: "PATCH", body }));
    if (done !== undefined) places.reload();
  }

  async function remove(place: QuickPlace) {
    if (!window.confirm(`Delete "${place.name}"?`)) return;
    const done = await action.run(() => api(`admin/quick-places/${place.id}/`, { method: "DELETE" }));
    if (done !== undefined) places.reload();
  }

  return (
    <>
      <PageHead title="Quick places" sub="The destination cards riders see under the search box. Smaller order numbers show first. Nothing here is hard-coded in the app."
                actions={<button className="btn" onClick={() => setOpen((v) => !v)}>{open ? "Close" : "New quick place"}</button>} />
      <ErrorBox message={action.error} />
      {open && (
        <form className="card" onSubmit={create} style={{ marginBottom: 16 }}>
          <h2>New quick place</h2>
          <div className="form-grid">
            <label className="field"><span>Card name</span><input value={form.name} onChange={(e) => set("name", e.target.value)} required maxLength={40} placeholder="Railway Station" />{err("name")}</label>
            <label className="field"><span>Icon</span>
              <select value={form.icon} onChange={(e) => set("icon", e.target.value)}>
                {ICONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select></label>
            <label className="field"><span>Latitude</span><input type="number" step="0.000001" value={form.latitude} onChange={(e) => set("latitude", e.target.value)} required />{err("latitude")}</label>
            <label className="field"><span>Longitude</span><input type="number" step="0.000001" value={form.longitude} onChange={(e) => set("longitude", e.target.value)} required />{err("longitude")}</label>
            <label className="field"><span>Full address</span><input value={form.address} onChange={(e) => set("address", e.target.value)} required maxLength={255} />{err("address")}</label>
            <label className="field"><span>Order</span><input type="number" min={0} value={form.sort_order} onChange={(e) => set("sort_order", e.target.value)} /></label>
          </div>
          <p className="sub">Tip: right-click the spot on Google Maps or OpenStreetMap and copy its latitude and longitude.</p>
          <div className="btn-row" style={{ marginTop: 14 }}><button className="btn" disabled={action.busy}>Add quick place</button></div>
        </form>
      )}
      <ErrorBox message={places.error} />
      <Table
        rows={places.data ?? []}
        rowKey={(p) => p.id}
        empty={places.loading ? "Loading…" : "No quick places yet. Riders see no cards until you add some."}
        columns={[
          { key: "name", title: "Card", render: (p) => <><strong>{p.name}</strong><div className="sub">{p.address}</div></> },
          { key: "icon", title: "Icon", render: (p) => ICONS.find(([v]) => v === p.icon)?.[1] ?? p.icon },
          { key: "loc", title: "Location", render: (p) => <span className="mono">{p.latitude}, {p.longitude}</span> },
          { key: "order", title: "Order", className: "num", render: (p) => (
            <input type="number" min={0} defaultValue={p.sort_order} style={{ width: 70 }}
                   onBlur={(e) => Number(e.target.value) !== p.sort_order && patch(p, { sort_order: Number(e.target.value) || 0 })} />
          ) },
          { key: "active", title: "Status", render: (p) => <Badge value={p.is_active ? "ACTIVE" : "HIDDEN"} tone={p.is_active ? "ok" : ""} /> },
          { key: "a", title: "", render: (p) => (
            <div className="btn-row">
              <button className="btn secondary small" disabled={action.busy} onClick={() => patch(p, { is_active: !p.is_active })}>{p.is_active ? "Hide" : "Show"}</button>
              <button className="btn secondary small" disabled={action.busy} onClick={() => remove(p)}>Delete</button>
            </div>
          ) },
        ]}
      />
    </>
  );
}
