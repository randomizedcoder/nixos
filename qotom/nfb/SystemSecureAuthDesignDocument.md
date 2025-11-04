# System Secure Auth Design Document

This document outlines the design and implementation of the system secure authentication system.

This will cover:
- ssh auth with google authenticator app on the phone
- freeradius authentication with google authenticator app on the phone

The ssh is to protect the system at /home/das/nixos/qotom/nfb/.  The same system will run the freeradius server, and then other routers will be configured to use freeradius for authentication.

# Design overview

## How Google Authenticator Works

Google Authenticator implements the Time-based One-Time Password (TOTP) algorithm as specified in RFC 6238. The system works as follows:

1. **Secret Key Generation**: When a user enrolls, a secret key is generated and shared between the server and the user's mobile device.

2. **QR Code Setup**: The secret key is typically encoded in a QR code that the user scans with the Google Authenticator app (or any compatible TOTP app).

3. **Token Generation**: The mobile app generates 6-digit codes that change every 30 seconds based on:
   - The shared secret key
   - The current Unix timestamp divided by 30
   - HMAC-SHA1 hashing algorithm

4. **Authentication Process**:
   - User enters username and password
   - System prompts for the 6-digit TOTP code
   - Server validates the code using the same algorithm
   - Access is granted if the code matches (within a time window tolerance)

5. **Time Synchronization**: Both the server and mobile device must have synchronized clocks (within ~30 seconds). The server validates codes for the current 30-second window and the previous/next window to account for slight time drift.

## Libraries and Packages Used

### For SSH Authentication:
- **`google-authenticator-libpam`**: PAM module that provides Google Authenticator support
- **`oath-toolkit`**: Optional command-line tools for managing OATH tokens
- **PAM (Pluggable Authentication Modules)**: Linux authentication framework

### For FreeRADIUS Authentication:
- **`freeradius`**: RADIUS server implementation
- **`freeradius.pam`**: PAM module plugin for FreeRADIUS (rlm_pam)
- **`google-authenticator-libpam`**: Shared PAM module for TOTP validation

## Authentication Flow

### SSH Authentication Flow:
```
User → SSH Client → SSH Server → PAM → Google Authenticator PAM Module → Validates TOTP Code
```

### FreeRADIUS Authentication Flow:
```
Router → RADIUS Request → FreeRADIUS Server → rlm_pam → PAM → Google Authenticator PAM Module → Validates TOTP Code
```

# SSH Authentication Configuration with NixOS

We will create a separate `.nix` file for SSH authentication: `services.ssh-google-auth.nix`

## Configuration Components:

1. **Enable Google Authenticator PAM module**:
   - Ensure `google-authenticator-libpam` package is available
   - Configure PAM to use the `pam_google_authenticator.so` module

2. **SSH Configuration**:
   - Enable `UsePAM = true` (already configured)
   - Enable `KbdInteractiveAuthentication = true` (already configured)
   - Set `ChallengeResponseAuthentication = true` (currently false)
   - Configure PAM to require Google Authenticator after password authentication

3. **PAM Configuration**:
   - Modify `/etc/pam.d/sshd` to include Google Authenticator
   - Use `auth required pam_google_authenticator.so` for 2FA enforcement
   - Configure to allow fallback for users without TOTP setup (optional)

4. **User Enrollment Process**:
   - Users run `google-authenticator` command to generate secret
   - QR code is displayed for scanning with mobile app
   - Secret is stored in `~/.google_authenticator`

## NixOS Module Structure:

```nix
{
  security.pam.services.sshd.googleAuthenticator = {
    enable = true;
    # Optional: allow users without TOTP configured
    # nullOk = true;
  };

  security.pam.services.sshd = {
    # Configure PAM stack for SSH
    # Password first, then TOTP
  };
}
```

# FreeRADIUS Authentication Configuration with NixOS

We will create a separate `.nix` file for FreeRADIUS: `services.freeradius.nix`

## Configuration Components:

1. **FreeRADIUS Server Setup**:
   - Enable FreeRADIUS service
   - Configure listening IP/port (default: UDP 1812 for authentication, 1813 for accounting)
   - Set shared secret for RADIUS clients (routers)

2. **PAM Module Integration**:
   - Configure `rlm_pam` module in FreeRADIUS
   - Point to PAM service configuration that uses Google Authenticator
   - Create `/etc/pam.d/radiusd` service file

3. **RADIUS Clients Configuration**:
   - Define authorized routers (NAS devices)
   - Configure shared secrets per client
   - Set IP addresses/networks for each client

4. **User Database**:
   - Use PAM for user authentication
   - Users must exist in system (`/etc/passwd` or LDAP)
   - TOTP secrets stored in `~/.google_authenticator` per user

## NixOS Module Structure:

```nix
{
  services.freeradius = {
    enable = true;
    # Configure clients (routers)
    clients = {
      "router1" = {
        ipaddr = "192.168.1.1";
        secret = "...";
      };
    };
    # Configure authentication modules
    extraModules = [ "pam" ];
    # Configure sites/default to use PAM
  };

  security.pam.services.radiusd = {
    # Configure PAM for FreeRADIUS
    googleAuthenticator.enable = true;
  };
}
```

# Testing Authentication

## Testing SSH Authentication:

1. **Initial Setup**:
   ```bash
   # On the server, as user 'das'
   google-authenticator
   # Follow prompts, scan QR code with phone app
   ```

2. **Test SSH Login**:
   ```bash
   # From another machine
   ssh das@nfbQotom
   # Should prompt for password first, then TOTP code
   ```

3. **Test with Public Key + TOTP** (if configured):
   ```bash
   ssh das@nfbQotom
   # Should prompt for TOTP code even with key auth
   ```

4. **Verify PAM Configuration**:
   ```bash
   # Check PAM config
   cat /etc/pam.d/sshd
   ```

## Testing FreeRADIUS:

1. **Install RADIUS Client Tools**:
   ```bash
   nix-shell -p freeradius
   ```

2. **Test Authentication**:
   ```bash
   # Test from server itself
   radtest username password localhost:1812 0 testing123

   # Should prompt or require TOTP code
   # Use: radtest username "password:TOTPCODE" localhost:1812 0 testing123
   ```

3. **Monitor FreeRADIUS Logs**:
   ```bash
   journalctl -u freeradius -f
   # Or check /var/log/freeradius/radius.log
   ```

4. **Test from Router** (if router supports RADIUS testing):
   - Configure router as RADIUS client
   - Attempt login
   - Verify authentication request appears in logs

5. **Test TOTP Validation**:
   ```bash
   # Generate code manually
   oathtool --totp -b $(cat ~/.google_authenticator | head -1)

   # Test with radtest
   radtest das "password:123456" localhost:1812 0 secret
   ```

# Router Configuration for FreeRADIUS

## General Router Configuration Steps:

1. **Obtain RADIUS Server Information**:
   - Server IP: `172.16.40.185` (nfbQotom)
   - Authentication Port: `1812` (UDP)
   - Accounting Port: `1813` (UDP)
   - Shared Secret: (configured in FreeRADIUS)

2. **Router-Specific Configuration**:

   ### Cisco Router (IOS/IOS-XE):
   ```
   aaa new-model
   aaa authentication login default group radius local
   radius server nfbQotom
    address ipv4 172.16.40.185 auth-port 1812 acct-port 1813
    key <shared-secret>
   ```

   ### Cisco ASA Firewall:
   See `cisco-asa-radius-quick-reference.txt` for complete configuration.
   ```
   ntp server 172.16.40.185 source management
   aaa-server nfbQotom protocol radius
   aaa-server nfbQotom (management) host 172.16.40.185
    key <shared-secret>
    authentication-port 1812
    accounting-port 1813
   aaa authentication ssh console nfbQotom LOCAL
   ```

   ### Juniper Router (JunOS):
   ```
   [edit]
   system {
     authentication-order [ radius password ];
     radius-server {
       172.16.40.185 {
         secret "<shared-secret>";
         port 1812;
       }
     }
   }
   ```

   ### pfSense/OPNsense:
   - Navigate to System > User Manager > Authentication Servers
   - Add RADIUS server
   - Server IP: `172.16.40.185`
   - Port: `1812`
   - Shared Secret: (configured secret)
   - Enable for login authentication

   ### VyOS:
   ```
   set system radius-server 172.16.40.185 secret '<shared-secret>'
   set system login authentication-order radius
   ```

3. **Time Synchronization (CRITICAL for TOTP)**:
   - TOTP codes are time-based and require synchronized clocks
   - Both router and RADIUS server must be within ~30 seconds of each other
   - Configure router to sync time from nfbQotom NTP server (172.16.40.185)
   - Verify time sync before testing RADIUS authentication
   - For Cisco ASA: `ntp server 172.16.40.185 source management`
   - Check sync status: `show ntp status` (ASA) or router equivalent

4. **Authentication Method**:
   - Most routers support password+TOTP via PAP (Password Authentication Protocol)
   - Format: `password:TOTPCODE` or `passwordTOTPCODE`
   - Some routers may require special formatting; check router documentation
   - Cisco ASA may prompt for password and TOTP separately

5. **Fallback Configuration**:
   - Consider configuring local fallback for emergency access
   - Example: `aaa authentication login default group radius local`
   - Keep a local admin account for emergency access

6. **Testing from Router**:
   - Verify time synchronization first (see step 3)
   - Attempt SSH/login with username
   - Router sends RADIUS request to nfbQotom
   - User enters password and TOTP code
   - FreeRADIUS validates via PAM/Google Authenticator
   - Router grants/denies access based on RADIUS response

## Security Considerations:

- Use strong shared secrets between routers and RADIUS server
- Consider IP-based restrictions in FreeRADIUS client configuration
- Monitor RADIUS authentication logs for suspicious activity
- Keep router firmware updated
- Use encrypted connections between routers and RADIUS server (if supported)

# Router Accounting and Auditing

## Overview

Router accounting provides comprehensive auditing of user activity on routers. This enables tracking of:
- User logins and logouts
- Session duration
- Commands executed on routers
- Network activity
- Security events

## Accounting Configuration

Accounting has been enabled in the FreeRADIUS configuration using the following modules:

### Detail Module

The `detail` module writes detailed accounting records to disk. Configuration:
- **Log Location**: `/var/log/radius/radacct/<router-ip>/detail-YYYYMMDD`
- **Format**: One directory per router IP address
- **Rotation**: One file per day (format: `detail-YYYYMMDD`)
- **Permissions**: 0600 (read/write for owner only)
- **Content**: Complete RADIUS accounting packets including timestamps, usernames, session information, and custom attributes

**Example log structure:**
```
/var/log/radius/radacct/
  ├── 192.168.1.1/
  │   ├── detail-20251031
  │   ├── detail-20251101
  │   └── ...
  ├── 192.168.1.2/
  │   ├── detail-20251031
  │   └── ...
  └── ...
```

### Unix Module

The `unix` module provides Unix-style accounting logs similar to wtmp:
- **Log Location**: `/var/log/radius/radwtmp`
- **Format**: Binary format compatible with standard Unix accounting tools
- **Purpose**: Session tracking and user activity history
- **Compatibility**: Can be parsed with standard Unix tools if needed

### Radutmp Module

The `radutmp` module tracks active user sessions:
- **Location**: `/var/run/radiusd/radutmp`
- **Purpose**: Real-time session tracking - shows who is currently logged in
- **Format**: Binary session database
- **Usage**: Query active sessions, detect concurrent logins

## Accounting Record Contents

RADIUS accounting records include:
- **User identification**: Username, session ID
- **Network information**: Source IP (router), NAS identifier
- **Timing**: Login time, logout time, session duration
- **Service type**: SSH, console, etc.
- **RADIUS attributes**: All standard RADIUS accounting attributes
- **Custom attributes**: Router-specific information if provided

## Accessing Accounting Records

### Viewing Detail Logs:
```bash
# View today's accounting for a specific router
cat /var/log/radius/radacct/192.168.1.1/detail-$(date +%Y%m%d)

# Search for specific user activity
grep "username" /var/log/radius/radacct/*/detail-*

# View accounting for date range
ls -la /var/log/radius/radacct/192.168.1.1/
```

### Querying Active Sessions:
```bash
# Use radwho (if available) or parse radutmp
cat /var/run/radiusd/radutmp
```

## Log Rotation

FreeRADIUS creates new detail files daily automatically. For long-term retention:
- Consider implementing log rotation policy (keep N days/weeks)
- Archive old accounting records
- Monitor disk space usage
- Consider centralizing logs for analysis

## Security and Privacy

- Accounting logs contain sensitive information (usernames, IP addresses, session data)
- Logs are stored with restrictive permissions (0600)
- Only root and radius user can read logs
- Consider encrypting archived accounting logs
- Implement log retention policies per organizational requirements

# FreeRADIUS systemd Security Hardening

## Overview

FreeRADIUS service should be hardened using systemd security features to reduce attack surface, limit resource usage, and improve overall security. This section documents the security design before implementation.

## Current Security Analysis

From `systemd-analyze security freeradius`, the current exposure level is **8.7 EXPOSED**, indicating significant room for improvement.

## Security Design Goals

1. **Resource Limits**: Constrain memory and CPU usage
2. **Process Isolation**: Limit access to system resources
3. **Network Security**: Restrict network access to only necessary operations
4. **File System Access**: Minimize file system access to required paths only
5. **Capability Restrictions**: Remove unnecessary Linux capabilities
6. **System Call Filtering**: Limit system calls to only those needed

## Proposed Security Configuration

### Resource Limits

- **Memory**: Limit to 150MB (MemoryMax = 150M)
- **CPU**: Limit to 1 core (CPUQuota = 100%, CPUAffinity = single core)
- **File Descriptors**: Reasonable limit based on expected client count
- **Process Count**: Limit concurrent processes

### Process Isolation

- **User/Group**: Already running as `radius` user (✓)
- **PrivateTmp**: Enable to isolate temporary files
- **PrivateDevices**: Enable to restrict hardware device access
- **PrivateNetwork**: Consider - FreeRADIUS needs network access, so this may not be applicable
- **PrivateUsers**: Evaluate - FreeRADIUS may need user lookups for PAM
- **ProtectHome**: Enable (already set)
- **ProtectSystem**: Enable with appropriate level (full or strict)
- **ProtectHostname**: Enable
- **ProtectClock**: Enable
- **ProtectKernelTunables**: Enable
- **ProtectKernelModules**: Enable
- **ProtectKernelLogs**: Enable
- **ProtectControlGroups**: Enable
- **ProtectProc**: Set to "invisible" or "noaccess"
- **ProcSubset**: Set to "pid"

### Network Security

- **RestrictAddressFamilies**: Allow only AF_INET, AF_INET6, AF_UNIX, AF_NETLINK
- **IPAddressDeny**: Deny all by default, allow only necessary
- **RestrictNetworkInterfaces**: Consider restricting to specific interfaces

### Capability Restrictions

- **CapabilityBoundingSet**: Remove all capabilities except those absolutely necessary
  - Keep: CAP_NET_BIND_SERVICE (to bind to ports < 1024)
  - Remove: CAP_SYS_ADMIN, CAP_SYS_PTRACE, CAP_SYS_TIME, CAP_DAC_OVERRIDE, etc.
- **AmbientCapabilities**: None (already set)
- **NoNewPrivileges**: Enable

### File System Access

- **ReadWritePaths**: Only `/var/log/radius`, `/var/run/radiusd`, `/var/log/radius/radacct`
- **ReadOnlyPaths**: `/etc/raddb`, `/etc/passwd`, `/etc/group` (for PAM user lookups)
- **InaccessiblePaths**: Restrict access to unnecessary paths
- **RootDirectory** or **RootImage**: Consider if additional isolation is needed

### System Call Filtering

- **SystemCallFilter**: Use `@system-service` profile as base, with minimal exclusions
- **SystemCallArchitectures**: Restrict to x86-64 only

### Other Security Settings

- **LockPersonality**: Enable
- **RestrictNamespaces**: Enable for all namespace types
- **RestrictRealtime**: Enable
- **RestrictSUIDSGID**: Enable
- **RemoveIPC**: Enable
- **MemoryDenyWriteExecute**: Enable
- **UMask**: Set to 0077 for secure file creation

### Security Trade-offs

Some restrictions may conflict with FreeRADIUS functionality:

1. **PrivateUsers**: May block PAM from accessing `/etc/passwd` - need to test
2. **ProtectSystem**: May need "full" instead of "strict" to allow log writing
3. **SystemCallFilter**: Must allow system calls needed for PAM, network operations, and file I/O
4. **ReadOnlyPaths**: Must include `/etc/passwd`, `/etc/group` for user lookups
5. **ReadWritePaths**: Must include log directories and runtime directories

### Testing Requirements

After applying security restrictions:
- Verify RADIUS authentication still works
- Verify PAM integration functions correctly
- Verify accounting logs are written properly
- Monitor for any permission errors
- Test with multiple concurrent connections

## Reference Implementation

See `atftpd.nix` for an example of comprehensive systemd security configuration with similar requirements (network service, user lookups, file operations).

## Target Security Score

Aim for security exposure level **≤ 3.0** (similar to atftpd which achieved 2.0), while maintaining full functionality.

# Implementation Plan

## Phase 1: SSH Google Authenticator Setup

1. **Create SSH Google Authenticator Module** (`services.ssh-google-auth.nix`):
   - Configure PAM to use Google Authenticator
   - Update SSH settings if needed
   - Test configuration before enforcing

2. **User Enrollment**:
   - Run `google-authenticator` for each user (das, nigel)
   - Document backup codes
   - Test SSH login with TOTP

3. **Verification**:
   - Verify SSH still works with TOTP
   - Test with public key + TOTP combination
   - Ensure fallback options work

## Phase 2: FreeRADIUS Setup

1. **Create FreeRADIUS Module** (`services.freeradius.nix`):
   - Configure FreeRADIUS service
   - Set up PAM integration
   - Configure default site for PAM authentication

2. **Initial Client Configuration**:
   - Add at least one test router/client
   - Configure shared secret
   - Test connectivity

3. **PAM Configuration for RADIUS**:
   - Create PAM service for radiusd
   - Integrate Google Authenticator
   - Test authentication locally

## Phase 3: Integration Testing

1. **Local Testing**:
   - Test FreeRADIUS authentication with radtest
   - Verify TOTP codes work through RADIUS
   - Check logs for errors

2. **Router Integration**:
   - Configure first router as RADIUS client
   - Test login from router
   - Verify TOTP prompt and validation

3. **Multi-User Testing**:
   - Test with multiple users
   - Verify user isolation (one user's TOTP doesn't work for another)

## Phase 4: Production Deployment

1. **Configuration Hardening**:
   - Review and tighten security settings
   - Set appropriate firewall rules
   - Configure log rotation

2. **Documentation**:
   - Document enrollment process
   - Create runbook for common issues
   - Document router configuration per router type

3. **Rollout to Additional Routers**:
   - Gradually add routers to RADIUS
   - Monitor for issues
   - Keep local fallback until stable

## Phase 5: Monitoring and Maintenance

1. **Logging Setup**:
   - Configure centralized logging (if applicable)
   - Set up alerts for authentication failures
   - Monitor RADIUS performance

2. **Backup and Recovery**:
   - Backup user `.google_authenticator` files
   - Document recovery procedures
   - Test backup restoration

3. **User Management**:
   - Document user enrollment process
   - Create procedures for user removal
   - Handle lost/compromised devices

## Files to Create:

1. `qotom/nfb/services.ssh-google-auth.nix` - SSH TOTP configuration
2. `qotom/nfb/services.freeradius.nix` - FreeRADIUS configuration
3. Update `qotom/nfb/configuration.nix` to import new modules

## Dependencies:

- `google-authenticator-libpam` - PAM module for TOTP
- `freeradius` - RADIUS server
- `oath-toolkit` - Optional: CLI tools for token management

## Testing Checklist:

- [ ] SSH login with password + TOTP works
- [ ] SSH login with public key + TOTP works (if configured)
- [ ] FreeRADIUS service starts successfully
- [ ] radtest authentication works locally
- [ ] Router can authenticate via RADIUS
- [ ] Multiple users can authenticate independently
- [ ] Logs show successful authentication
- [ ] Invalid TOTP codes are rejected
- [ ] Time drift tolerance works (codes valid for ~90 seconds window)

# Implementation Progress

## Phase 1: SSH Google Authenticator Setup

- [x] **Design Document Completed** - All sections filled in with technical details
- [x] **Create services.ssh-google-auth.nix** - NixOS module for SSH TOTP configuration ✅
- [x] **Update services.ssh.nix** - Enable ChallengeResponseAuthentication ✅
- [x] **Update configuration.nix** - Import new SSH auth module ✅
- [ ] **Test NixOS Configuration** - Verify configuration compiles
- [ ] **User Enrollment** - Run `google-authenticator` for users
- [ ] **SSH Login Testing** - Verify password + TOTP works

## Phase 2: FreeRADIUS Setup

- [x] **Create services.freeradius.nix** - NixOS module for FreeRADIUS ✅
- [x] **Configure PAM Integration** - Set up radiusd PAM service ✅
- [x] **Configure RADIUS Clients** - Added Cisco ASA (172.16.40.30) client configuration ✅
- [x] **Update configuration.nix** - Import FreeRADIUS module ✅
- [x] **Fix Configuration Syntax** - Corrected to use environment.etc for config files ✅
- [x] **Add radiusd.conf** - Created main FreeRADIUS configuration file ✅
- [x] **Enable PAM Module** - Override package to include PAM support ✅
- [x] **Simplify Site Configuration** - Removed EAP dependencies ✅
- [x] **Enable Accounting Modules** - Added detail, unix, and radutmp for auditing ✅
- [x] **Fix Deprecated Configuration** - Updated perm to permissions in radutmp ✅
- [x] **Add Listen Sections** - Configured authentication and accounting ports ✅
- [x] **Test FreeRADIUS Service** - Service starts successfully ✅
- [x] **Apply Systemd Security Hardening** - Added comprehensive security restrictions ✅
- [x] **Fix Directory Creation** - Added tmpfiles rules for required directories ✅
- [x] **Fix Namespace Issues** - Corrected ReadOnlyPaths/InaccessiblePaths for proper isolation ✅
- [x] **Create chrony.nix** - Configured NTP server for time synchronization ✅
- [x] **Configure chronyd** - Enabled with security hardening, resource limits, and priority ✅
- [x] **Verify Time Sync** - chronyd syncing with upstream NTP pool servers ✅
- [x] **Configure Cisco ASA NTP** - ASA syncing time from nfbQotom (172.16.40.185) ✅
- [x] **Verify Time Sync Accuracy** - ASA showing 2.49ms offset (acceptable for TOTP) ✅
- [x] **Create ASA Configuration Files** - Created cisco-asa-radius-config.txt and quick reference ✅
- [x] **Verify Security Score** - Security exposure level: 3.4 OK ✅
- [x] **User Enrollment** - Google Authenticator configured for user 'das' ✅
- [x] **Fix BlastRADIUS Warnings** - Updated localhost client to require Message-Authenticator ✅
- [ ] **Configure Cisco ASA** - Apply RADIUS configuration to firewall
- [ ] **Test ASA RADIUS Authentication** - Verify authentication from Cisco ASA works

## Phase 3: Integration Testing

- [ ] **FreeRADIUS Authentication Testing** - Verify TOTP codes work via RADIUS
- [x] **Router Integration** - Cisco ASA configuration prepared (see cisco-asa-radius-quick-reference.txt) ✅
- [ ] **Test ASA RADIUS Authentication** - Verify authentication from Cisco ASA firewall works
- [ ] **Password+TOTP Format Testing** - Verify correct format (password:TOTPCODE or separate prompts)
- [ ] **Multi-User Testing** - Test with multiple users (das, nigel)
- [ ] **Log Verification** - Check authentication logs and accounting records
- [ ] **Error Handling Testing** - Verify invalid TOTP codes are rejected properly

## Phase 4: Production Deployment

- [x] **Time Synchronization** - chronyd and ASA time sync configured and verified ✅
- [x] **Firewall Rules** - UDP 123 (NTP) and UDP 1812/1813 (RADIUS) ports configured ✅
- [ ] **Configuration Hardening** - Review security settings
- [ ] **Log Rotation** - Set up log management
- [ ] **Documentation** - Complete operational docs

## Phase 5: Monitoring and Maintenance

- [ ] **Logging Setup** - Configure centralized logging
- [ ] **Backup Procedures** - Backup TOTP secrets
- [ ] **User Management Procedures** - Document enrollment/removal

## Files Status

- [x] `SystemSecureAuthDesignDocument.md` - ✅ Completed
- [x] `services.ssh-google-auth.nix` - ✅ Created
- [x] `services.freeradius.nix` - ✅ Created
- [x] `services.ssh.nix` - ✅ Updated (ChallengeResponseAuthentication enabled)
- [x] `configuration.nix` - ✅ Updated (imports added)
- [x] `chrony.nix` - ✅ Created (NTP server with security hardening)
- [x] `cisco-asa-radius-config.txt` - ✅ Created (detailed ASA configuration guide)
- [x] `cisco-asa-radius-quick-reference.txt` - ✅ Created (quick reference for ASA commands)
