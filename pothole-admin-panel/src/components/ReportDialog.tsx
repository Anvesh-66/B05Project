"use client";

import { useEffect, useRef, useState } from "react";

import { AlertIcon, CheckIcon, CloseIcon, TrashIcon } from "@/components/Icons";
import { LevelBadge, LocationLink } from "@/components/ReportsTable";
import {
  deleteReport,
  fetchReport,
  fetchReportImage,
  formatDate,
  type ReportDetail,
  STATUS_LABELS,
} from "@/lib/api";
import { LEVEL_LABELS, riskLevel, severityLevel } from "@/lib/labels";

interface Props {
  token: string;
  reportId: number;
  onClose: () => void;
  onDeleted: () => void;
  onError: (error: unknown) => void;
}

export default function ReportDialog({ token, reportId, onClose, onDeleted, onError }: Props) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [report, setReport] = useState<ReportDetail | null>(null);
  const [kind, setKind] = useState<"annotated" | "original">("annotated");
  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);

  // <dialog> only becomes modal (backdrop, Esc to close, focus trap) through showModal().
  useEffect(() => {
    const dialog = dialogRef.current;
    if (dialog && !dialog.open) dialog.showModal();
  }, []);

  useEffect(() => {
    let cancelled = false;
    fetchReport(token, reportId)
      .then((detail) => {
        if (!cancelled) setReport(detail);
      })
      .catch((e) => {
        if (cancelled) return;
        onClose();
        onError(e);
      });
    return () => {
      cancelled = true;
    };
  }, [token, reportId, onClose, onError]);

  useEffect(() => {
    let cancelled = false;
    let url: string | null = null;
    setImageUrl(null);
    fetchReportImage(token, reportId, kind)
      .then((blob) => {
        if (cancelled) return;
        url = URL.createObjectURL(blob);
        setImageUrl(url);
      })
      .catch((e) => {
        if (!cancelled) onError(e);
      });
    return () => {
      cancelled = true;
      if (url) URL.revokeObjectURL(url);
    };
  }, [token, reportId, kind, onError]);

  async function remove() {
    if (!window.confirm(`Delete report #${reportId} and its photos? This cannot be undone.`)) return;
    setDeleting(true);
    try {
      await deleteReport(token, reportId);
      onDeleted();
    } catch (e) {
      onClose();
      onError(e);
    }
  }

  const level = report ? riskLevel(report.risk) : null;

  return (
    <dialog ref={dialogRef} onClose={onClose} aria-label={`Report ${reportId}`}>
      <div className="dlg-head">
        <h2>Report #{reportId}</h2>
        <div className="segmented" role="group" aria-label="Photo version">
          <button type="button" aria-pressed={kind === "annotated"} onClick={() => setKind("annotated")}>
            Detections
          </button>
          <button type="button" aria-pressed={kind === "original"} onClick={() => setKind("original")}>
            Original
          </button>
        </div>
        <button className="btn btn-icon" type="button" onClick={onClose} aria-label="Close">
          <CloseIcon />
        </button>
      </div>

      <div className="dlg-body">
        {imageUrl ? (
          // The photo is a blob fetched with the auth header, so next/image cannot load it.
          <img
            className="photo"
            src={imageUrl}
            alt={kind === "annotated" ? "Photo with detected potholes outlined" : "Original photo"}
          />
        ) : (
          <div className="photo-placeholder">Loading photo…</div>
        )}

        {report && level ? (
          <>
            <div className={`risk-banner level-${level}`}>
              {level === "low" ? <CheckIcon /> : <AlertIcon />}
              <div>
                <b>{LEVEL_LABELS[level]} risk</b>
                <span>
                  {report.detection_count} {report.detection_count === 1 ? "pothole" : "potholes"} found ·{" "}
                  {report.severe_count} high severity
                </span>
              </div>
            </div>

            <dl className="facts">
              <div>
                <dt>Reporter</dt>
                <dd>
                  {report.reporter_name} · {report.reporter_email}
                </dd>
              </div>
              <div>
                <dt>Status</dt>
                <dd>{STATUS_LABELS[report.status]}</dd>
              </div>
              <div>
                <dt>Reported</dt>
                <dd>{formatDate(report.created_at)}</dd>
              </div>
              <div>
                <dt>Resolved</dt>
                <dd>{formatDate(report.resolved_at)}</dd>
              </div>
              <div>
                <dt>Location</dt>
                <dd>
                  <LocationLink latitude={report.latitude} longitude={report.longitude} />
                </dd>
              </div>
            </dl>

            <div>
              <div className="section-label">Detections</div>
              <ol className="detections">
                {report.detections.map((d, i) => {
                  const percent = Math.round(d.confidence * 100);
                  return (
                    <li key={i}>
                      <span className="index">{i + 1}</span>
                      <span className="name">{d.class_name}</span>
                      <LevelBadge level={severityLevel(d.severity)} suffix="severity" />
                      <div className="confidence">
                        <div className="bar">
                          <i style={{ width: `${percent}%` }} />
                        </div>
                        {percent}% confidence
                      </div>
                      <div className="depth">
                        {d.has_water
                          ? "Water in pothole, depth not measured"
                          : d.depth_index == null
                            ? "Depth not measured"
                            : `Depth index ${d.depth_index.toFixed(2)}`}
                      </div>
                    </li>
                  );
                })}
              </ol>
            </div>
          </>
        ) : (
          <div style={{ display: "grid", gap: 10 }}>
            <span className="skeleton" style={{ height: 56 }} />
            <span className="skeleton" style={{ width: "60%" }} />
            <span className="skeleton" style={{ width: "40%" }} />
          </div>
        )}
      </div>

      <div className="dlg-foot">
        <button className="btn btn-danger" type="button" onClick={remove} disabled={deleting}>
          <TrashIcon />
          {deleting ? "Deleting…" : "Delete report"}
        </button>
      </div>
    </dialog>
  );
}
