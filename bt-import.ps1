param([string]$InputFile = "bt-keys-export.json")

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "ERROR: Run as Administrator first" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $InputFile)) { Write-Host "ERROR: File not found: $InputFile" -ForegroundColor Red; exit 1 }

# Enable SeTakeOwnershipPrivilege and fix registry permissions
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using Microsoft.Win32;
using System.Security.Principal;

public static class RegFix {
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool SetNamedSecurityInfo(string pObjectName, int ObjectType, int SecurityInfo, byte[] psidOwner, byte[] psidGroup, byte[] pDacl, byte[] pSacl);

    [StructLayout(LayoutKind.Sequential)]
    private struct TOKEN_PRIVILEGES { public int PrivilegeCount; public long Luid; public int Attributes; }

    private const uint TOKEN_QUERY = 0x0008;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const int SE_PRIVILEGE_ENABLED = 0x2;
    private const int SE_REGISTRY_KEY = 1;
    private const int OWNER_SECURITY_INFORMATION = 1;
    private const int DACL_SECURITY_INFORMATION = 4;

    public static void EnableTakeOwnershipPrivilege() {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_ADJUST_PRIVILEGES, out token))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        long luid;
        if (!LookupPrivilegeValue(null, "SeTakeOwnershipPrivilege", out luid))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES { PrivilegeCount = 1, Luid = luid, Attributes = SE_PRIVILEGE_ENABLED };
        if (!AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }

    public static void SetOwnerToAdmins(string keyPath) {
        EnableTakeOwnershipPrivilege();
        var admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        byte[] sidBytes = new byte[admins.BinaryLength];
        admins.GetBinaryForm(sidBytes, 0);
        int rc = Marshal.GetLastWin32Error();
        if (!SetNamedSecurityInfo(keyPath, SE_REGISTRY_KEY, OWNER_SECURITY_INFORMATION, sidBytes, null, null, null))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }

    public static void GrantAdminsFullControl(string keyPath) {
        var key = Registry.LocalMachine.OpenSubKey(keyPath, RegistryKeyPermissionCheck.ReadWriteSubTree, RegistryRights.ChangePermissions);
        if (key == null) throw new UnauthorizedAccessException("Cannot open key for permission change");
        var acl = key.GetAccessControl();
        acl.SetAccessRuleProtection(false, true);
        acl.AddAccessRule(new RegistryAccessRule("BUILTIN\\Administrators", RegistryRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        key.SetAccessControl(acl);
        key.Close();
    }
}
'@

$regPath = "SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
try {
    [RegFix]::SetOwnerToAdmins($regPath)
    Write-Host "Took ownership of Bluetooth Keys registry." -ForegroundColor Green
    [RegFix]::GrantAdminsFullControl($regPath)
    Write-Host "Granted Administrators Full Control." -ForegroundColor Green
} catch {
    Write-Host "Warning: $_" -ForegroundColor Yellow
}

$data = Get-Content $InputFile -Raw | ConvertFrom-Json
$regBase = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
$count = 0
foreach ($adapter in $data) {
    $adapterMac = ($adapter.mac -replace ':', '').ToLower()
    $adapterPath = "$regBase\$adapterMac"
    if (-not (Test-Path $adapterPath)) { $null = New-Item -Path $adapterPath -Force }
    foreach ($device in $adapter.devices) {
        $deviceMac = ($device.mac -replace ':', '').ToLower()
        $keyBytes = [byte[]]::new($device.key.Length / 2)
        for ($i = 0; $i -lt $device.key.Length; $i += 2) {
            $keyBytes[$i / 2] = [Convert]::ToByte($device.key.Substring($i, 2), 16)
        }
        try {
            Set-ItemProperty -Path $adapterPath -Name $deviceMac -Value $keyBytes -Type Binary -ErrorAction Stop
            Write-Host "  [OK] $($device.mac) - $($device.name)" -ForegroundColor Green; $count++
        } catch {
            Write-Host "  [FAIL] $($device.mac) - $($device.name): $_" -ForegroundColor Red
        }
    }
}
Write-Host "Imported $count key(s). Reboot for changes to take effect." -ForegroundColor Cyan
