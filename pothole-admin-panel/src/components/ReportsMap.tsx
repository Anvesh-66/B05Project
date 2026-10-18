"use client";

import "leaflet/dist/leaflet.css";

import type { Map as LeafletMap } from "leaflet";
import { useEffect, useRef, useState } from "react";

import { PinIcon } from "@/components/Icons";
import { fetchLocatedReports, type ReportStatus, type ReportSummary, STATUS_LABELS } from "@/lib/api";
import { LEVEL_LABELS, riskLevel } from "@/lib/labels";

interface Props {
  token: string;
  /** Changes when reports were added, removed or edited, so the map reloads. */
  version: number;
  onView: (id: number) => void;
  onError: (error: unknown) => void;
}

// Same colours as the status dropdown in the table.
const STATUS_COLORS: Record<ReportStatus, string> = {
  pending: "#f5a524",
  in_review: "#70a9ff",
  resolved: "#3dd68c",
};

// Higher risk draws a larger dot.
const RISK_RADIUS = { low: 7, medium: 9, high: 12 };

export default function ReportsMap({ token, version, onView, onError }: Props) {
  const container = useRef<HTMLDivElement>(null);
  const [reports, setReports] = useState<ReportSummary[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchLocatedReports(token)
      .then((located) => {
        if (!cancelled) setReports(located);
      })
      .catch((e) => {
        if (cancelled) return;
        setReports([]);
        onError(e);
      });
    return () => {
      cancelled = true;
    };
  }, [token, version, onError]);

  useEffect(() => {
    if (!reports || reports.length === 0 || !container.current) return;
    let cancelled = false;
    let map: LeafletMap | null = null;

    // Leaflet touches `window` when it loads, so it can only be imported in the browser.
    import("leaflet").then((L) => {
      if (cancelled || !container.current) return;
      map = L.map(container.current);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      }).addTo(map);

      const points = reports.map((report) => {
        const level = riskLevel(report.risk);
        const point = L.latLng(report.latitude!, report.longitude!);
        L.circleMarker(point, {
          radius: RISK_RADIUS[level],
          color: "#0d1119",
          weight: 2,
          fillColor: STATUS_COLORS[report.status],
          fillOpacity: 0.95,
        })
          .bindTooltip(`#${report.id} · ${LEVEL_LABELS[level]} risk · ${STATUS_LABELS[report.status]}`)
          .on("click", () => onView(report.id))
          .addTo(map!);
        return point;
      });
      map.fitBounds(L.latLngBounds(points).pad(0.2), { maxZoom: 16 });
    });

    return () => {
      cancelled = true;
      map?.remove();
    };
  }, [reports, onView]);

  return (
    <section className="panel">
      <div className="toolbar">
        <h3>Report map</h3>
        <div className="legend">
          {(Object.keys(STATUS_LABELS) as ReportStatus[]).map((status) => (
            <span key={status}>
              <i style={{ background: STATUS_COLORS[status] }} />
              {STATUS_LABELS[status]}
            </span>
          ))}
          <span className="dim">Larger dot = higher risk</span>
        </div>
      </div>

      {reports === null ? (
        <div className="map map-message dim">Loading report locations…</div>
      ) : reports.length === 0 ? (
        <div className="empty">
          <PinIcon />
          <b>No reports with a location yet</b>
          <span>Photos taken with the camera in the mobile app attach their location.</span>
        </div>
      ) : (
        <div className="map" ref={container} role="application" aria-label="Map of reported potholes" />
      )}
    </section>
  );
}
