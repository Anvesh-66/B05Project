"""Email notification service for pothole reports."""

from __future__ import annotations

import logging
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Literal

logger = logging.getLogger("uvicorn.error")


def _get_smtp_config() -> dict[str, str | int] | None:
    """Read SMTP configuration from environment variables."""
    host = os.getenv("SMTP_HOST", "").strip()
    port = os.getenv("SMTP_PORT", "587").strip()
    user = os.getenv("SMTP_USER", "").strip()
    password = os.getenv("SMTP_PASSWORD", "").strip()
    from_email = os.getenv("SMTP_FROM_EMAIL", "").strip()
    from_name = os.getenv("SMTP_FROM_NAME", "Pothole Detection System").strip()

    if not all([host, user, password, from_email]):
        return None

    try:
        port_int = int(port)
    except ValueError:
        logger.warning("Invalid SMTP_PORT value: %s", port)
        return None

    return {
        "host": host,
        "port": port_int,
        "user": user,
        "password": password,
        "from_email": from_email,
        "from_name": from_name,
    }


def _send_email(to_email: str, subject: str, html_body: str) -> bool:
    """Send an email via SMTP. Returns True on success, False on failure."""
    config = _get_smtp_config()
    if config is None:
        logger.info("Email not sent: SMTP not configured")
        return False

    try:
        msg = MIMEMultipart("alternative")
        msg["From"] = f"{config['from_name']} <{config['from_email']}>"
        msg["To"] = to_email
        msg["Subject"] = subject

        msg.attach(MIMEText(html_body, "html"))

        with smtplib.SMTP(str(config["host"]), int(config["port"])) as server:
            server.starttls()
            server.login(str(config["user"]), str(config["password"]))
            server.send_message(msg)

        logger.info("Email sent to %s: %s", to_email, subject)
        return True

    except Exception as e:
        logger.warning("Failed to send email to %s: %s", to_email, e)
        return False


def _format_status(status: str) -> str:
    """Convert status to display format."""
    status_map = {
        "pending": "Pending Review",
        "in_review": "In Review",
        "resolved": "Resolved",
    }
    return status_map.get(status.lower(), status.title())


def _format_risk(risk: str) -> str:
    """Convert risk level to display format."""
    risk_map = {
        "LOW": "Low Risk",
        "MED": "Medium Risk",
        "HIGH": "High Risk",
    }
    return risk_map.get(risk.upper(), risk)


def _get_status_color(status: str) -> str:
    """Get color for status badge."""
    colors = {
        "pending": "#FF9800",
        "in_review": "#2196F3",
        "resolved": "#4CAF50",
    }
    return colors.get(status.lower(), "#757575")


def _get_risk_color(risk: str) -> str:
    """Get color for risk badge."""
    colors = {
        "HIGH": "#D32F2F",
        "MED": "#FF9800",
        "LOW": "#4CAF50",
    }
    return colors.get(risk.upper(), "#757575")


def send_report_submitted_email(
    to_email: str,
    user_name: str,
    report_id: int,
    detection_count: int,
    severe_count: int,
    risk: str,
    address: str | None,
    area: str | None,
    created_at: str,
) -> bool:
    """Send email notification when a report is submitted."""
    location = address or area or "Location not available"
    if address and area:
        location = f"{address}, {area}"

    subject = f"Pothole Report #{report_id} Submitted Successfully"

    html_body = f"""
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
                    <!-- Header -->
                    <tr>
                        <td style="background: linear-gradient(135deg, #0061A4 0%, #004d82 100%); padding: 40px 30px; text-align: center;">
                            <h1 style="margin: 0; color: #ffffff; font-size: 28px; font-weight: 600;">Report Submitted Successfully</h1>
                            <p style="margin: 10px 0 0 0; color: #D1E4FF; font-size: 16px;">Your pothole report has been received</p>
                        </td>
                    </tr>
                    
                    <!-- Content -->
                    <tr>
                        <td style="padding: 40px 30px;">
                            <p style="margin: 0 0 20px 0; color: #333333; font-size: 16px; line-height: 1.6;">
                                Dear <strong>{user_name}</strong>,
                            </p>
                            <p style="margin: 0 0 30px 0; color: #555555; font-size: 15px; line-height: 1.6;">
                                Thank you for helping improve road safety! Your pothole report has been successfully submitted and is now under review by our team.
                            </p>
                            
                            <!-- Report Details Box -->
                            <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f8f9fa; border-radius: 8px; border-left: 4px solid #0061A4; margin-bottom: 30px;">
                                <tr>
                                    <td style="padding: 25px;">
                                        <h2 style="margin: 0 0 20px 0; color: #0061A4; font-size: 20px; font-weight: 600;">Report Details</h2>
                                        
                                        <table width="100%" cellpadding="8" cellspacing="0">
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Report Number:</td>
                                                <td style="color: #333333; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">#{report_id}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Submission Date:</td>
                                                <td style="color: #333333; font-size: 14px; padding: 8px 0; text-align: right;">{created_at}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Location:</td>
                                                <td style="color: #333333; font-size: 14px; padding: 8px 0; text-align: right;">{location}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Potholes Detected:</td>
                                                <td style="color: #333333; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">{detection_count}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Severe Potholes:</td>
                                                <td style="color: #D32F2F; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">{severe_count}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Risk Level:</td>
                                                <td style="padding: 8px 0; text-align: right;">
                                                    <span style="background-color: {_get_risk_color(risk)}; color: #ffffff; padding: 6px 12px; border-radius: 4px; font-size: 12px; font-weight: 600; text-transform: uppercase;">{_format_risk(risk)}</span>
                                                </td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Status:</td>
                                                <td style="padding: 8px 0; text-align: right;">
                                                    <span style="background-color: #FF9800; color: #ffffff; padding: 6px 12px; border-radius: 4px; font-size: 12px; font-weight: 600;">Pending Review</span>
                                                </td>
                                            </tr>
                                        </table>
                                    </td>
                                </tr>
                            </table>
                            
                            <!-- What's Next -->
                            <div style="background-color: #E3F2FD; border-radius: 8px; padding: 20px; margin-bottom: 30px;">
                                <h3 style="margin: 0 0 12px 0; color: #0061A4; font-size: 16px; font-weight: 600;">📋 What Happens Next?</h3>
                                <ol style="margin: 0; padding-left: 20px; color: #555555; font-size: 14px; line-height: 1.8;">
                                    <li>Our team will review your report within 24-48 hours</li>
                                    <li>The report status will be updated as work progresses</li>
                                    <li>You'll receive email notifications on status changes</li>
                                    <li>Once resolved, you'll be notified of completion</li>
                                </ol>
                            </div>
                            
                            <p style="margin: 0 0 10px 0; color: #555555; font-size: 14px; line-height: 1.6;">
                                You can track your report status anytime through the mobile app. We appreciate your contribution to making our roads safer!
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
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
"""

    return _send_email(to_email, subject, html_body)


def send_status_changed_email(
    to_email: str,
    user_name: str,
    report_id: int,
    old_status: str,
    new_status: str,
    risk: str,
    address: str | None,
    area: str | None,
    detection_count: int,
    resolved_at: str | None,
) -> bool:
    """Send email notification when report status is changed by admin."""
    location = address or area or "Location not available"
    if address and area:
        location = f"{address}, {area}"

    status_messages = {
        "in_review": "Our team is actively reviewing your pothole report and assessing the situation.",
        "resolved": "Great news! The pothole issue has been addressed and marked as resolved.",
    }

    status_icons = {
        "pending": "⏳",
        "in_review": "🔍",
        "resolved": "✅",
    }

    message = status_messages.get(new_status.lower(), "Your report status has been updated.")
    icon = status_icons.get(new_status.lower(), "📢")

    subject = f"Report #{report_id} Status Update: {_format_status(new_status)}"

    html_body = f"""
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
                    <!-- Header -->
                    <tr>
                        <td style="background: linear-gradient(135deg, {_get_status_color(new_status)} 0%, {_get_status_color(new_status)}dd 100%); padding: 40px 30px; text-align: center;">
                            <div style="font-size: 48px; margin-bottom: 10px;">{icon}</div>
                            <h1 style="margin: 0; color: #ffffff; font-size: 28px; font-weight: 600;">Status Updated</h1>
                            <p style="margin: 10px 0 0 0; color: rgba(255,255,255,0.9); font-size: 16px;">Report #{report_id}</p>
                        </td>
                    </tr>
                    
                    <!-- Content -->
                    <tr>
                        <td style="padding: 40px 30px;">
                            <p style="margin: 0 0 20px 0; color: #333333; font-size: 16px; line-height: 1.6;">
                                Dear <strong>{user_name}</strong>,
                            </p>
                            <p style="margin: 0 0 30px 0; color: #555555; font-size: 15px; line-height: 1.6;">
                                {message}
                            </p>
                            
                            <!-- Status Change Box -->
                            <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom: 30px;">
                                <tr>
                                    <td align="center" style="padding: 20px; background-color: #f8f9fa; border-radius: 8px;">
                                        <div style="display: inline-block; text-align: center;">
                                            <span style="background-color: {_get_status_color(old_status)}; color: #ffffff; padding: 8px 16px; border-radius: 4px; font-size: 14px; font-weight: 600;">{_format_status(old_status)}</span>
                                            <span style="margin: 0 15px; color: #999999; font-size: 20px;">→</span>
                                            <span style="background-color: {_get_status_color(new_status)}; color: #ffffff; padding: 8px 16px; border-radius: 4px; font-size: 14px; font-weight: 600;">{_format_status(new_status)}</span>
                                        </div>
                                    </td>
                                </tr>
                            </table>
                            
                            <!-- Report Summary -->
                            <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f8f9fa; border-radius: 8px; border-left: 4px solid {_get_status_color(new_status)}; margin-bottom: 30px;">
                                <tr>
                                    <td style="padding: 25px;">
                                        <h2 style="margin: 0 0 20px 0; color: #333333; font-size: 18px; font-weight: 600;">Report Summary</h2>
                                        
                                        <table width="100%" cellpadding="8" cellspacing="0">
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Report Number:</td>
                                                <td style="color: #333333; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">#{report_id}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Location:</td>
                                                <td style="color: #333333; font-size: 14px; padding: 8px 0; text-align: right;">{location}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Potholes Detected:</td>
                                                <td style="color: #333333; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">{detection_count}</td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Risk Level:</td>
                                                <td style="padding: 8px 0; text-align: right;">
                                                    <span style="background-color: {_get_risk_color(risk)}; color: #ffffff; padding: 6px 12px; border-radius: 4px; font-size: 12px; font-weight: 600; text-transform: uppercase;">{_format_risk(risk)}</span>
                                                </td>
                                            </tr>
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Current Status:</td>
                                                <td style="padding: 8px 0; text-align: right;">
                                                    <span style="background-color: {_get_status_color(new_status)}; color: #ffffff; padding: 6px 12px; border-radius: 4px; font-size: 12px; font-weight: 600;">{_format_status(new_status)}</span>
                                                </td>
                                            </tr>"""

    if resolved_at:
        html_body += f"""
                                            <tr>
                                                <td style="color: #666666; font-size: 14px; padding: 8px 0;">Resolved On:</td>
                                                <td style="color: #4CAF50; font-size: 14px; font-weight: 600; padding: 8px 0; text-align: right;">{resolved_at}</td>
                                            </tr>"""

    html_body += """
                                        </table>
                                    </td>
                                </tr>
                            </table>
"""

    if new_status.lower() == "resolved":
        html_body += """
                            <!-- Thank You Message -->
                            <div style="background-color: #E8F5E9; border-radius: 8px; padding: 20px; margin-bottom: 20px; text-align: center;">
                                <h3 style="margin: 0 0 10px 0; color: #2E7D32; font-size: 18px; font-weight: 600;">🎉 Thank You!</h3>
                                <p style="margin: 0; color: #555555; font-size: 14px; line-height: 1.6;">
                                    Your report has helped make our roads safer. We appreciate your vigilance and contribution to the community!
                                </p>
                            </div>
"""
    else:
        html_body += """
                            <div style="background-color: #E3F2FD; border-radius: 8px; padding: 20px; margin-bottom: 20px;">
                                <p style="margin: 0; color: #555555; font-size: 14px; line-height: 1.6;">
                                    💡 <strong>Tip:</strong> You can check your report status anytime through the mobile app. We'll keep you updated via email as progress is made.
                                </p>
                            </div>
"""

    html_body += """
                            <p style="margin: 0; color: #555555; font-size: 14px; line-height: 1.6;">
                                If you have any questions or concerns about your report, please don't hesitate to contact our support team.
                            </p>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
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
"""

    return _send_email(to_email, subject, html_body)
