import type { RiskLevel } from "@/lib/api";

/** A level shown to the admin as Low / Medium / High. The key doubles as a CSS modifier. */
export type Level = "low" | "medium" | "high";

export const LEVEL_LABELS: Record<Level, string> = { low: "Low", medium: "Medium", high: "High" };

/** Report risk from the backend: LOW, MED or HIGH. */
export function riskLevel(risk: RiskLevel | string): Level {
  if (risk === "HIGH") return "high";
  if (risk === "MED") return "medium";
  return "low";
}

/** Pothole severity from the backend: "Severe", "Neutral" or "Not Severe". */
export function severityLevel(severity: string): Level {
  const value = severity.toLowerCase();
  if (value === "severe") return "high";
  if (value === "not severe") return "low";
  return "medium";
}

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  const last = parts.length > 1 ? parts[parts.length - 1][0] : "";
  return (parts[0][0] + last).toUpperCase();
}
