# Quick Start Script for Pothole Detection System with Email Notifications
# This script helps you start all services with proper configuration

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Pothole Detection System - Quick Start                    ║" -ForegroundColor Cyan
Write-Host "║     Email Notifications: ENABLED ✅                            ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check configuration
$backendEnv = "pothole-detection-app\.env"
$adminEnv = "pothole-admin-panel\.env.local"

Write-Host "Checking configuration..." -ForegroundColor Yellow

if (Test-Path $backendEnv) {
    Write-Host "✅ Backend .env found" -ForegroundColor Green
} else {
    Write-Host "❌ Backend .env NOT found!" -ForegroundColor Red
    Write-Host "   Create it from .env.example" -ForegroundColor Yellow
}

if (Test-Path $adminEnv) {
    Write-Host "✅ Admin Panel .env.local found" -ForegroundColor Green
} else {
    Write-Host "❌ Admin Panel .env.local NOT found!" -ForegroundColor Red
    Write-Host "   Create it from .env.example" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Menu
Write-Host "What would you like to start?" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Backend Server (FastAPI)" -ForegroundColor White
Write-Host "  2. Admin Panel (Next.js)" -ForegroundColor White
Write-Host "  3. Both (Backend + Admin Panel)" -ForegroundColor White
Write-Host "  4. Test Email Configuration" -ForegroundColor White
Write-Host "  5. View Setup Guide" -ForegroundColor White
Write-Host "  6. Exit" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Enter your choice (1-6)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "Starting Backend Server..." -ForegroundColor Green
        Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
        Write-Host ""
        Set-Location "pothole-detection-app"
        & .\.venv\Scripts\Activate.ps1
        uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
    }
    "2" {
        Write-Host ""
        Write-Host "Starting Admin Panel..." -ForegroundColor Green
        Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
        Write-Host ""
        Set-Location "pothole-admin-panel"
        npm run dev
    }
    "3" {
        Write-Host ""
        Write-Host "Starting Both Services..." -ForegroundColor Green
        Write-Host ""
        Write-Host "⚠️ This will open 2 new PowerShell windows" -ForegroundColor Yellow
        Write-Host "   Close them to stop the services" -ForegroundColor Yellow
        Write-Host ""
        
        # Start backend in new window
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD\pothole-detection-app'; .\.venv\Scripts\Activate.ps1; Write-Host 'Backend Server Starting...' -ForegroundColor Green; uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000"
        
        # Wait a bit for backend to start
        Start-Sleep -Seconds 3
        
        # Start admin panel in new window
        Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD\pothole-admin-panel'; Write-Host 'Admin Panel Starting...' -ForegroundColor Green; npm run dev"
        
        Write-Host ""
        Write-Host "✅ Services started in separate windows!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Backend:     http://127.0.0.1:8000" -ForegroundColor Cyan
        Write-Host "Admin Panel: http://localhost:3000" -ForegroundColor Cyan
        Write-Host ""
    }
    "4" {
        Write-Host ""
        Write-Host "Testing Email Configuration..." -ForegroundColor Green
        Write-Host ""
        Set-Location "pothole-detection-app"
        python scripts\test_smtp_connection.py
        Write-Host ""
        Read-Host "Press Enter to continue"
    }
    "5" {
        Write-Host ""
        Get-Content "EMAIL_SETUP_COMPLETE.txt"
        Write-Host ""
        Read-Host "Press Enter to continue"
    }
    "6" {
        Write-Host ""
        Write-Host "Goodbye! 👋" -ForegroundColor Cyan
        Write-Host ""
        exit
    }
    default {
        Write-Host ""
        Write-Host "Invalid choice. Please run the script again." -ForegroundColor Red
        Write-Host ""
    }
}
