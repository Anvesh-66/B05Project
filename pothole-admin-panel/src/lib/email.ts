import nodemailer from "nodemailer";
import type { ReportDetail, ReportStatus, RiskLevel } from "./api";

interface SmtpConfig {
  host: string;
  port: number;
  user: string;
  password: string;
  fromEmail: string;
  fromName: string;
}

function getSmtpConfig(): SmtpConfig | null {
  const host = process.env.SMTP_HOST?.trim();
  const port = process.env.SMTP_PORT?.trim() || "587";
  const user = process.env.SMTP_USER?.trim();
  const password = process.env.SMTP_PASSWORD?.trim();
  const fromEmail = process.env.SMTP_FROM_EMAIL?.trim();
  const fromName = process.env.SMTP_FROM_NAME?.trim() || "Pothole Admin Panel";

  if (!host || !user || !password || !fromEmail) {
    return null;
  }

  const portNum = parseInt(port, 10);
  if (isNaN(portNum)) {
    console.warn("Invalid SMTP_PORT value:", port);
    return null;
  }

  return {
    host,
    port: portNum,
    user,
    password,
    fromEmail,
    fromName,
  };
}

function formatStatus(status: ReportStatus): string {
  const statusMap: Record<ReportStatus, string> = {
    pending: "Pending Review",
    in_review: "In Review",
    resolved: "Resolved",
  };
  return statusMap[status] || status;
}

function formatRisk(risk: RiskLevel): string {
  const riskMap: Record<RiskLevel, string> = {
    LOW: "Low Risk",
    MED: "Medium Risk",
    HIGH: "High Risk",
  };
  return riskMap[risk] || risk;
}

function getStatusColor(status: ReportStatus): string {
  const colors: Record<ReportStatus, string> = {
    pending: "#FF9800",
    in_review: "#2196F3",
    resolved: "#4CAF50",
  };
  return colors[status] || "#757575";
}

function getRiskColor(risk: RiskLevel): string {
  const colors: Record<RiskLevel, string> = {
    HIGH: "#D32F2F",
    MED: "#FF9800",
    LOW: "#4CAF50",
  };
  return colors[risk] || "#757575";
}

export async function sendStatusChangeEmail(
  toEmail: string,
  userName: string,
  report: ReportDetail,
  oldStatus: ReportStatus,
  newStatus: ReportStatus
): Promise<boolean> {
  const config = getSmtpConfig();
  if (!config) {
    console.info("Email not sent: SMTP not configured");
    return false;
  }

  const location =
    report.address && report.area
      ? `${report.address}, ${report.area}`
      : report.address || report.area || "Location not available";

  const statusMessages: Record<ReportStatus, string> = {
    in_review: "Our team is actively reviewing this pothole report and assessing the situation.",
    resolved: "Great news! The pothole issue has been addressed and marked as resolved.",
    pending: "The report status has been updated.",
  };

  const statusIcons: Record<ReportStatus, string> = {
    pending: "⏳",
    in_review: "🔍",
    resolved: "✅",
  };

  const message = statusMessages[newStatus] || "The report status has been updated.";
  const icon = statusIcons[newStatus] || "📢";

  const subject = `Report #${report.id} Status Update: ${formatStatus(newStatus)}`;

  let htmlBody = `
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
    <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f5f5f5; padding: 20px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" style="background-color: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
                    <tr>
                        <td style="background: linear-gradient(135deg, ${getStatusColor(newStatus)} 0%, ${getStatusColor(newStatus)}dd 100%); padding: 40px 30px; text-align: center;">
                            <div style="font-size: 48px; margin-bottom: 10px;">${icon}</div>
                            <h1 style="margin: 0; color: #ffffff; font-size: 28px; font-weight: 600;">Status Updated</h1>
                            <p style="margin: 10px 0 0 0; color: rgba(255,255,255,0.9); font-size: 16px;">Report #${report.id}</p>
                        </td>
                    </tr>
                    
                    <tr>
                        <td style="padding: 40px 30px;">
                            <p style="margin: 0 0 20px 0; color: #333333; font-size: 16px; line-height: 1.6;">
                                Dear <strong>${userName}</strong>,
                            </p>
                            <p style="margin: 0 0 30px 0; color: #555555; font-size: 15px; line-height: 1.6;">
                                ${message}
                            </p>
                            
                            <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 30px;">
                                <tr>
                                    <td align="center" style="padding: 20px; background-color: #f8f9fa; border-radius: 8px;">
                                        <div style="display: inline-block; text-align: center;">
                                            <span style="background-color: ${getStatusColor(oldStatus)}; color: #ffffff; padding: 8px 16px; border-radius: 4px; font-size: 14px; font-weight: 600;">${formatStatus(oldStatus)}</span>
                                            <span style="margin: 0 15px; color: #999999; font-size: 20px;">→</span>
                                            <span style="background-color: ${getStatusColor(newStatus)}; color: #ffffff; padding: 8px 16px; border-radius: 4px; font-size: 14px; font-weight: 600;">${formatStatus(newStatus)}</span>
                                        </div>
                                    </td>
                                </tr>
                            </table>
                            
                            <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f8f9fa; border-radius: 8px; border-left: 4px solid ${getStatusColor(newStatus)}; margin-bottom: 30px;">
                                <tr>
                                    <td style="padding: 25px;">
                                        <h2 style="margin: 0 0 20px 0; color: #333333; font-size: 18px; font-weight: 600;">Report Summary</h2>
                                        
                                        <table width="100%" cellpadding="8" cellspacing="0">
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Report Number:</td>
                                                <td style="color: #333333; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">#${report.id}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Location:</td>
                                                <td style="color: #333333; font-size: 14px; padding: 8px 0; text-align: right;">${location}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Potholes Detected:</td>
                                                <td style="color: #333333; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">${report.detection_count}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Risk Level:</td>
                                                <td style="padding: 8px 0; text-align: right;">
                                                    <span style="background-color: ${getRiskColor(report.risk)}; color: #ffffff; padding: 6px 12px; border-radius: 4px; font-size: 12px; font-weight: 600; text-transform: uppercase;">${formatRisk(report.risk)}</span>
                                                </td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Current Status:</td>
                                                <td style="padding: 8px 0; text-align: right;">
                                                    <span style="background-color: ${getStatusColor(newStatus)}; color: #ffffff; padding: 6px 12px; border-radius: 4px; font-size: 12px; font-weight: 600;">${formatStatus(newStatus)}</span>
                                                </td>
                                            </tr>`;

  if (report.resolved_at) {
    htmlBody += `
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Resolved On:</td>
                                                <td style="color: #4CAF50; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">${report.resolved_at}</td>
                                            </tr>`;
  }

  htmlBody += `
                                        </table>
                                    </td>
                                </tr>
                            </table>
`;

  if (newStatus === "resolved") {
    htmlBody += `
                            <div style="background-color: #E8F5E9; border-radius: 8px; padding: 20px; margin-bottom: 20px; text-align: center;">
                                <h3 style="margin: 0 0 10px 0; color: #2E7D32; font-size: 18px; font-weight: 600;">🎉 Thank You!</h3>
                                <p style="margin: 0; color: #555555; font-size: 14px; line-height: 1.6;">
                                    Your report has helped make our roads safer. We appreciate your vigilance and contribution to the community!
                                </p>
                            </div>
`;
  } else {
    htmlBody += `
                            <div style="background-color: #E3F2FD; border-radius: 8px; padding: 20px; margin-bottom: 20px;">
                                <p style="margin: 0; color: #555555; font-size: 14px; line-height: 1.6;">
                                    💡 <strong>Tip:</strong> You can check your report status anytime through the mobile app. We'll keep you updated via email as progress is made.
                                </p>
                            </div>
`;
  }

  htmlBody += `
                            <p style="margin: 0; color: #555555; font-size: 14px; line-height: 1.6;">
                                If you have any questions or concerns about your report, please don't hesitate to contact our support team.
                            </p>
                        </td>
                    </tr>
                    
                    <tr>
                        <td style="background-color: #f8f9fa; padding: 30px; text-align: center; border-top: 1px solid #e0e0e0;">
                            <p style="margin: 0 0 10px 0; color: #666666; font-size: 13px;">
                                This is an automated notification from the Pothole Detection System
                            </p>
                            <p style="margin: 0; color: #999999; font-size: 12px;">
                                © 2026 Pothole Detection System. All rights reserved.
                            </p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
`;

  try {
    const transporter = nodemailer.createTransport({
      host: config.host,
      port: config.port,
      secure: config.port === 465,
      auth: {
        user: config.user,
        pass: config.password,
      },
    });

    await transporter.sendMail({
      from: `"${config.fromName}" <${config.fromEmail}>`,
      to: toEmail,
      subject,
      html: htmlBody,
    });

    console.log("Email sent to:", toEmail, "Subject:", subject);
    return true;
  } catch (error) {
    console.error("Failed to send email:", error);
    return false;
  }
}
