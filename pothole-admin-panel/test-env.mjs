// Test if environment variables are loaded in Next.js
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Read .env.local file
const envPath = path.join(__dirname, '.env.local');
console.log('='.repeat(50));
console.log('Next.js Environment Variables Test');
console.log('='.repeat(50));

if (fs.existsSync(envPath)) {
  console.log('\n✅ Found .env.local file');
  const content = fs.readFileSync(envPath, 'utf-8');
  
  const vars = {};
  content.split('\n').forEach(line => {
    line = line.trim();
    if (line && !line.startsWith('#') && line.includes('=')) {
      const [key, ...valueParts] = line.split('=');
      vars[key.trim()] = valueParts.join('=').trim();
    }
  });
  
  console.log('\nSMTP_HOST:', vars.SMTP_HOST || '(not set)');
  console.log('SMTP_PORT:', vars.SMTP_PORT || '(not set)');
  console.log('SMTP_USER:', vars.SMTP_USER || '(not set)');
  console.log('SMTP_PASSWORD:', vars.SMTP_PASSWORD ? '*'.repeat(vars.SMTP_PASSWORD.length) : '(not set)');
  console.log('SMTP_FROM_EMAIL:', vars.SMTP_FROM_EMAIL || '(not set)');
  console.log('SMTP_FROM_NAME:', vars.SMTP_FROM_NAME || '(not set)');
  console.log('BACKEND_URL:', vars.BACKEND_URL || '(not set)');
  
  if (vars.SMTP_HOST && vars.SMTP_USER && vars.SMTP_PASSWORD && vars.SMTP_FROM_EMAIL) {
    console.log('\n✅ All required SMTP variables are set!');
    console.log('\n📝 Next steps:');
    console.log('   1. Restart the Next.js dev server to load these variables');
    console.log('   2. Test by changing a report status in the admin panel');
  } else {
    console.log('\n❌ Missing SMTP configuration!');
  }
} else {
  console.log('\n❌ .env.local file not found!');
  console.log('Create it by copying .env.example');
}
