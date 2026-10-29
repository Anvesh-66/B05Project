"""Test SMTP connection and configuration."""
import os
import smtplib
from email.mime.text import MIMEText
from pathlib import Path

def load_env():
    """Load .env file manually."""
    env_file = Path(__file__).parent.parent / ".env"
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    os.environ[key.strip()] = value.strip()
        print(f"✅ Loaded .env from {env_file}")
    else:
        print(f"⚠️ No .env file found at {env_file}")

def test_smtp():
    """Test SMTP configuration."""
    print("=" * 50)
    print("SMTP Configuration Test")
    print("=" * 50)
    
    # Load .env file
    load_env()
    
    # Read configuration
    host = os.getenv("SMTP_HOST", "").strip()
    port = os.getenv("SMTP_PORT", "587").strip()
    user = os.getenv("SMTP_USER", "").strip()
    password = os.getenv("SMTP_PASSWORD", "").strip()
    from_email = os.getenv("SMTP_FROM_EMAIL", "").strip()
    
    print(f"\nSMTP_HOST: {host or '(not set)'}")
    print(f"SMTP_PORT: {port}")
    print(f"SMTP_USER: {user or '(not set)'}")
    print(f"SMTP_PASSWORD: {'*' * len(password) if password else '(not set)'}")
    print(f"SMTP_FROM_EMAIL: {from_email or '(not set)'}")
    
    # Check if all required fields are set
    if not all([host, user, password, from_email]):
        print("\n❌ ERROR: Missing required SMTP configuration!")
        print("Please set all required environment variables in .env file")
        return False
    
    try:
        port_int = int(port)
    except ValueError:
        print(f"\n❌ ERROR: Invalid SMTP_PORT value: {port}")
        return False
    
    print(f"\n🔄 Testing connection to {host}:{port_int}...")
    
    try:
        # Try to connect
        server = smtplib.SMTP(host, port_int, timeout=10)
        server.set_debuglevel(0)  # Set to 1 for verbose output
        
        print("✅ Connected to SMTP server")
        
        # Start TLS
        print("🔄 Starting TLS...")
        server.starttls()
        print("✅ TLS started")
        
        # Try to login
        print("🔄 Attempting login...")
        server.login(user, password)
        print("✅ Login successful!")
        
        # Try to send a test email to yourself
        print(f"\n🔄 Sending test email to {user}...")
        msg = MIMEText("This is a test email from Pothole Detection System.\n\nSMTP configuration is working correctly!")
        msg["Subject"] = "SMTP Test - Pothole Detection System"
        msg["From"] = from_email
        msg["To"] = user
        
        server.send_message(msg)
        print("✅ Test email sent successfully!")
        print(f"\n📧 Check your inbox at {user}")
        
        server.quit()
        
        print("\n" + "=" * 50)
        print("✅ ALL TESTS PASSED - SMTP is configured correctly!")
        print("=" * 50)
        return True
        
    except smtplib.SMTPAuthenticationError as e:
        print(f"\n❌ Authentication failed: {e}")
        print("\nPossible reasons:")
        print("  1. Incorrect username or password")
        print("  2. For Gmail, you need an App Password (not your regular password)")
        print("  3. Generate one at: https://myaccount.google.com/apppasswords")
        print("  4. Make sure 2-Step Verification is enabled on your Google account")
        print("  5. Password should be 16 characters without spaces (e.g., abcdabcdabcdabcd)")
        return False
        
    except smtplib.SMTPException as e:
        print(f"\n❌ SMTP error: {e}")
        return False
        
    except Exception as e:
        print(f"\n❌ Connection error: {e}")
        print("\nPossible reasons:")
        print("  1. Incorrect SMTP host or port")
        print("  2. Network/firewall blocking the connection")
        print("  3. SMTP server is down")
        return False

if __name__ == "__main__":
    test_smtp()
