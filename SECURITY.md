# TavaBharat Migration - Security Best Practices

Security guidelines and best practices for the AWS Lightsail deployment.

## Table of Contents

- [Infrastructure Security](#infrastructure-security)
- [Database Security](#database-security)
- [Application Security](#application-security)
- [Network Security](#network-security)
- [Access Control](#access-control)
- [Data Protection](#data-protection)
- [Monitoring and Logging](#monitoring-and-logging)
- [Incident Response](#incident-response)
- [Compliance](#compliance)
- [Security Checklist](#security-checklist)

## Infrastructure Security

### Server Hardening

**1. Keep System Updated**
```bash
# Regular updates (weekly)
sudo apt-get update
sudo apt-get upgrade -y

# Check for security updates
sudo apt-get update
sudo apt-get dist-upgrade -y

# Enable automatic security updates
sudo apt-get install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

**2. SSH Security**
```bash
# Disable password authentication (use keys only)
sudo nano /etc/ssh/sshd_config

# Set these values:
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes

# Restart SSH
sudo systemctl restart sshd

# Change default SSH port (optional but recommended)
Port 2222  # Choose a non-standard port
```

**3. Install Fail2Ban**
```bash
# Install
sudo apt-get install fail2ban

# Configure
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local

# Enable for SSH, Nginx
[sshd]
enabled = true
port = 22
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
port = http,https
maxretry = 5

# Start service
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check status
sudo fail2ban-client status
```

**4. Configure Firewall Properly**
```bash
# Default deny, explicit allow
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow only necessary ports
sudo ufw allow 22/tcp   # SSH (or your custom port)
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS

# Enable firewall
sudo ufw enable

# Review rules
sudo ufw status numbered
```

## Database Security

### MSSQL Security

**1. Strong Password Policy**
```bash
# SA password requirements:
# - Minimum 12 characters (not just 8)
# - Uppercase and lowercase letters
# - Numbers
# - Special characters
# - No dictionary words
# - Change regularly (every 90 days)

# Generate strong password
openssl rand -base64 20
```

**2. Principle of Least Privilege**
```sql
-- Don't use SA account for applications
-- Create specific users with minimal permissions

-- For API 1 (read/write on specific tables)
CREATE USER [api1_user] WITH PASSWORD = 'StrongPassword123!@#';

-- Grant only needed permissions
USE TavaBharatDB_Prod;
ALTER ROLE db_datareader ADD MEMBER [api1_user];
ALTER ROLE db_datawriter ADD MEMBER [api1_user];

-- Grant execute on specific procedures only
GRANT EXECUTE ON SCHEMA::dbo TO [api1_user];

-- Deny dangerous permissions
DENY ALTER ANY USER TO [api1_user];
DENY DROP ANY TABLE TO [api1_user];
```

**3. Network Isolation**
```bash
# MSSQL should listen on localhost only (default)
# Verify:
sudo netstat -tuln | grep 1433

# Should show:
# tcp 0 0 127.0.0.1:1433 0.0.0.0:* LISTEN

# If exposed to 0.0.0.0, configure network
sudo /opt/mssql/bin/mssql-conf set network.ipaddress 127.0.0.1
sudo systemctl restart mssql-server
```

**4. Enable Auditing**
```sql
-- Enable SQL Server audit
USE master;
GO

CREATE SERVER AUDIT TavaBharatAudit
TO FILE ( 
    FILEPATH = '/var/opt/mssql/audit/',
    MAXSIZE = 100 MB,
    MAX_ROLLOVER_FILES = 10
)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
GO

ALTER SERVER AUDIT TavaBharatAudit WITH (STATE = ON);
GO

-- Audit database access
USE TavaBharatDB_Prod;
GO

CREATE DATABASE AUDIT SPECIFICATION DatabaseAudit
FOR SERVER AUDIT TavaBharatAudit
ADD (DATABASE_OBJECT_ACCESS_GROUP),
ADD (DATABASE_OBJECT_CHANGE_GROUP)
WITH (STATE = ON);
GO
```

**5. Encrypt Connections**
```bash
# Already configured with TrustServerCertificate=True
# For production, use proper certificates:

# Generate certificate
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /var/opt/mssql/mssql.key \
  -out /var/opt/mssql/mssql.pem \
  -days 365

# Configure MSSQL to use certificate
sudo /opt/mssql/bin/mssql-conf set network.tlscert /var/opt/mssql/mssql.pem
sudo /opt/mssql/bin/mssql-conf set network.tlskey /var/opt/mssql/mssql.key
sudo /opt/mssql/bin/mssql-conf set network.forceencryption 1

sudo systemctl restart mssql-server
```

**6. Database Backup Encryption**
```sql
-- Encrypt backups
BACKUP DATABASE [TavaBharatDB_Prod]
TO DISK = '/var/backups/mssql/encrypted_backup.bak'
WITH COMPRESSION,
     ENCRYPTION (
         ALGORITHM = AES_256,
         SERVER CERTIFICATE = TavaBharatBackupCert
     );
```

## Application Security

### .NET API Security

**1. Secure Configuration**
```bash
# Protect .env files
chmod 600 /var/www/api1/.env
chmod 600 /var/www/api2/.env
chown ubuntu:ubuntu /var/www/api*/.env

# Never commit .env files to git
# Store production secrets in environment variables
```

**2. HTTPS Only (in production)**
```json
// appsettings.Production.json
{
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://localhost:5000"
      }
    }
  },
  "RequireHttpsMetadata": true,
  "ForceHttps": true
}
```

**3. Security Headers**
```csharp
// In Startup.cs or Program.cs
app.Use(async (context, next) =>
{
    context.Response.Headers.Add("X-Frame-Options", "SAMEORIGIN");
    context.Response.Headers.Add("X-Content-Type-Options", "nosniff");
    context.Response.Headers.Add("X-XSS-Protection", "1; mode=block");
    context.Response.Headers.Add("Referrer-Policy", "strict-origin-when-cross-origin");
    context.Response.Headers.Add("Content-Security-Policy", 
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'");
    
    await next();
});
```

**4. Input Validation**
```csharp
// Always validate and sanitize input
[HttpPost]
public IActionResult Create([FromBody] UserDto user)
{
    // Validate
    if (!ModelState.IsValid)
        return BadRequest(ModelState);
    
    // Sanitize
    user.Name = Sanitize(user.Name);
    
    // Process...
}

// Use parameterized queries (Entity Framework does this)
// NEVER concatenate user input into SQL
```

**5. Rate Limiting**
```csharp
// Install: AspNetCoreRateLimit
services.AddMemoryCache();
services.Configure<IpRateLimitOptions>(options =>
{
    options.GeneralRules = new List<RateLimitRule>
    {
        new RateLimitRule
        {
            Endpoint = "*",
            Limit = 100,
            Period = "1m"
        }
    };
});
services.AddSingleton<IRateLimitConfiguration, RateLimitConfiguration>();
```

**6. Authentication & Authorization**
```csharp
// Use JWT tokens
services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = Configuration["Jwt:Issuer"],
            ValidAudience = Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(Configuration["Jwt:Key"]))
        };
    });

// Use strong, random JWT secret
// Store in environment variable, not in code
```

### Frontend Security

**1. Content Security Policy**
```html
<!-- In index.html or via meta tag -->
<meta http-equiv="Content-Security-Policy" 
      content="default-src 'self'; 
               script-src 'self' 'unsafe-inline' 'unsafe-eval'; 
               style-src 'self' 'unsafe-inline';">
```

**2. Sanitize User Input**
```typescript
// Angular
import { DomSanitizer } from '@angular/platform-browser';

constructor(private sanitizer: DomSanitizer) {}

displayUserContent(content: string) {
  return this.sanitizer.sanitize(SecurityContext.HTML, content);
}

// React
import DOMPurify from 'dompurify';

function UserContent({ html }) {
  return <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(html) }} />;
}
```

**3. Secure API Calls**
```typescript
// Use HTTPS
const API_BASE = 'https://yourdomain.com/api/v1';

// Include auth token
const headers = {
  'Authorization': `Bearer ${token}`,
  'Content-Type': 'application/json'
};

// Validate responses
fetch(`${API_BASE}/data`, { headers })
  .then(res => {
    if (!res.ok) throw new Error('API error');
    return res.json();
  })
  .catch(err => {
    // Handle error securely, don't expose details to user
    console.error('Error:', err);
    showUserMessage('An error occurred');
  });
```

## Network Security

### Nginx Security

**1. SSL/TLS Configuration**
```nginx
# Strong SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;

# HSTS
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
```

**2. Rate Limiting**
```nginx
# Define rate limit zones
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=1r/s;

# Apply to locations
location /api/v1 {
    limit_req zone=api_limit burst=20 nodelay;
    # ... proxy settings
}

location /api/v1/auth/login {
    limit_req zone=login_limit burst=5;
    # ... proxy settings
}
```

**3. Hide Version Information**
```nginx
# In nginx.conf
server_tokens off;
```

**4. Request Size Limits**
```nginx
client_max_body_size 10M;
client_body_buffer_size 128k;
large_client_header_buffers 4 16k;
```

**5. Prevent Clickjacking**
```nginx
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
```

## Access Control

### User Access Management

**1. SSH Key Management**
```bash
# Generate strong SSH key (on local machine)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy to server
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@YOUR_IP

# Disable password authentication (see SSH Security above)
```

**2. Sudo Access**
```bash
# Limit sudo access
# Only specific users should have sudo

# View sudoers
sudo visudo

# Grant limited sudo to user
username ALL=(ALL) /usr/bin/systemctl restart api1, /usr/bin/systemctl restart api2
```

**3. Application-Level RBAC**
```sql
-- Database roles for different access levels
CREATE ROLE readonly_user;
GRANT SELECT ON SCHEMA::dbo TO readonly_user;

CREATE ROLE admin_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO admin_user;

-- Assign users to roles
ALTER ROLE readonly_user ADD MEMBER [report_user];
ALTER ROLE admin_user ADD MEMBER [api_user];
```

## Data Protection

### Sensitive Data Handling

**1. Encrypt Sensitive Data at Rest**
```sql
-- Transparent Data Encryption (TDE) - Enterprise Edition only
-- For Express, encrypt at column level

-- Create master key
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongPassword123!';

-- Create certificate
CREATE CERTIFICATE TavaBharatCert
WITH SUBJECT = 'TavaBharat Certificate';

-- Create symmetric key
CREATE SYMMETRIC KEY TavaBharatKey
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE TavaBharatCert;

-- Encrypt data
OPEN SYMMETRIC KEY TavaBharatKey
DECRYPTION BY CERTIFICATE TavaBharatCert;

UPDATE Users
SET EncryptedData = EncryptByKey(Key_GUID('TavaBharatKey'), SensitiveData);

CLOSE SYMMETRIC KEY TavaBharatKey;
```

**2. PII Data Protection**
```csharp
// Mask PII in logs
public class PiiMaskingMiddleware
{
    public async Task Invoke(HttpContext context)
    {
        // Don't log sensitive fields
        var excludeFields = new[] { "password", "ssn", "creditCard" };
        
        // Log only masked data
    }
}
```

**3. Secure Backup Storage**
```bash
# Encrypt backups before uploading to S3
gpg --symmetric --cipher-algo AES256 backup.bak

# Upload encrypted file
aws s3 cp backup.bak.gpg s3://bucket/backups/

# Decrypt when needed
gpg --decrypt backup.bak.gpg > backup.bak
```

## Monitoring and Logging

### Security Monitoring

**1. Enable Comprehensive Logging**
```bash
# Already configured by 10-monitoring.sh

# Additional security logs
sudo nano /etc/rsyslog.d/50-tavabharat.conf

# Add:
:msg, contains, "Failed password" /var/log/tavabharat/auth-failures.log
:msg, contains, "authentication failure" /var/log/tavabharat/auth-failures.log
```

**2. Log Monitoring**
```bash
# Install log analysis tool
sudo apt-get install logwatch

# Configure daily reports
sudo nano /etc/logwatch/conf/logwatch.conf

# Set:
Output = mail
MailTo = admin@yourdomain.com
Detail = High
```

**3. Intrusion Detection**
```bash
# Install AIDE (Advanced Intrusion Detection Environment)
sudo apt-get install aide

# Initialize database
sudo aideinit

# Check for changes daily
sudo aide --check

# Add to cron
echo "0 5 * * * root /usr/bin/aide --check > /var/log/aide-check.log 2>&1" | sudo tee /etc/cron.d/aide
```

### Alert Configuration

```bash
# Configure email alerts for critical events
cat > /usr/local/bin/security-alert.sh << 'EOF'
#!/bin/bash
ALERT_EMAIL="admin@yourdomain.com"

# Monitor auth failures
FAILURES=$(grep "Failed password" /var/log/auth.log | wc -l)
if [ $FAILURES -gt 10 ]; then
    echo "Warning: $FAILURES failed login attempts" | \
        mail -s "Security Alert: Failed Logins" $ALERT_EMAIL
fi

# Monitor disk usage
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 90 ]; then
    echo "Warning: Disk usage at $DISK_USAGE%" | \
        mail -s "Security Alert: Disk Space" $ALERT_EMAIL
fi
EOF

chmod +x /usr/local/bin/security-alert.sh

# Add to cron (hourly)
echo "0 * * * * root /usr/local/bin/security-alert.sh" | sudo tee /etc/cron.d/security-alerts
```

## Incident Response

### Incident Response Plan

**1. Detection**
- Monitor logs continuously
- Set up alerts for anomalies
- Review health checks

**2. Containment**
```bash
# If breach detected:

# 1. Isolate affected system
sudo ufw deny from SUSPICIOUS_IP

# 2. Stop compromised service
sudo systemctl stop api1  # or affected service

# 3. Take snapshot
# Do this from Lightsail console

# 4. Collect evidence
sudo tar -czf /tmp/evidence-$(date +%Y%m%d).tar.gz \
    /var/log/tavabharat \
    /var/log/nginx \
    /var/log/auth.log

# 5. Change all passwords
```

**3. Eradication**
```bash
# Remove malicious content
# Patch vulnerabilities
# Update all packages
sudo apt-get update && sudo apt-get upgrade -y
```

**4. Recovery**
```bash
# Restore from clean backup
# Verify integrity
# Monitor closely
```

**5. Lessons Learned**
- Document incident
- Update security measures
- Train team

## Compliance

### Data Protection Compliance

**1. GDPR Considerations (if applicable)**
- Implement data minimization
- Enable data export functionality
- Implement right to be forgotten
- Log all data access
- Encrypt PII

**2. Data Retention**
```sql
-- Implement data retention policy
-- Delete old data after retention period

-- Example: Delete records older than 7 years
DELETE FROM OldTable
WHERE CreatedDate < DATEADD(YEAR, -7, GETDATE());
```

**3. Audit Trail**
```sql
-- Maintain audit trail for all changes
CREATE TABLE AuditLog (
    Id INT IDENTITY PRIMARY KEY,
    TableName NVARCHAR(100),
    Action NVARCHAR(10),
    UserId INT,
    Timestamp DATETIME DEFAULT GETDATE(),
    OldValue NVARCHAR(MAX),
    NewValue NVARCHAR(MAX)
);

-- Trigger example
CREATE TRIGGER tr_Users_Audit ON Users
AFTER UPDATE, DELETE
AS
BEGIN
    INSERT INTO AuditLog (TableName, Action, UserId, OldValue)
    SELECT 'Users', 'UPDATE', UserId, 
        (SELECT * FROM deleted FOR JSON PATH)
    FROM deleted;
END;
```

## Security Checklist

### Pre-Deployment

- [ ] All scripts reviewed for security issues
- [ ] Passwords meet complexity requirements
- [ ] SSH key authentication configured
- [ ] Firewall rules configured correctly
- [ ] SSL/TLS certificates obtained
- [ ] Security headers configured
- [ ] Input validation implemented
- [ ] Authentication/authorization tested

### Post-Deployment

- [ ] Change all default passwords
- [ ] Disable root login
- [ ] Configure fail2ban
- [ ] Enable automatic updates
- [ ] Set up monitoring and alerts
- [ ] Configure log rotation
- [ ] Test backup and restore
- [ ] Document all credentials (store securely)
- [ ] Review and harden Nginx config
- [ ] Enable database auditing
- [ ] Configure HTTPS redirect
- [ ] Test rate limiting

### Ongoing

- [ ] Weekly security updates
- [ ] Monthly password rotation
- [ ] Quarterly security audit
- [ ] Review logs daily
- [ ] Test backups monthly
- [ ] Update documentation
- [ ] Review access logs
- [ ] Check for CVEs affecting stack
- [ ] Penetration testing (annually)

## Security Tools

### Recommended Tools

**1. Security Scanning**
```bash
# Install Lynis
sudo apt-get install lynis

# Run security audit
sudo lynis audit system

# Review recommendations
cat /var/log/lynis.log
```

**2. Vulnerability Scanning**
```bash
# Install ClamAV (antivirus)
sudo apt-get install clamav clamav-daemon

# Update virus definitions
sudo freshclam

# Scan system
sudo clamscan -r /var/www
```

**3. SSL Testing**
```bash
# Test SSL configuration
curl -I https://yourdomain.com

# Or use online tools:
# - SSL Labs: https://www.ssllabs.com/ssltest/
# - Security Headers: https://securityheaders.com/
```

## References

- OWASP Top 10: https://owasp.org/www-project-top-ten/
- CIS Benchmarks: https://www.cisecurity.org/cis-benchmarks/
- NIST Cybersecurity Framework: https://www.nist.gov/cyberframework
- AWS Security Best Practices: https://aws.amazon.com/security/security-resources/

---

**Remember: Security is an ongoing process, not a one-time task. Regularly review and update security measures.**
