# Get-SSHEnabledStatus

## Synopsis

Returns the SSH status on an ESX host.

## Syntax

```powershell
Get-SSHEnabledStatus [-server] <String> [-user] <String> [-pass] <String> [<CommonParameters>]
```

## Description

The `Get-SSHEnabledStatus` cmdlet creates a new SSH session to a specified ESX host to see if SSH is enabled and returns true if SSH is enabled.

## Examples

### Example 1

```powershell
Get-SSHEnabledStatus -server [esx_fqdn] -user [admin_username] -pass [admin_password]
```

This example checks if SSH is enabled on the specified ESX host.

## Parameters

### -server

The FQDN of the ESX host.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -user

The username to authenticate to the ESX host.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -pass

The password to authenticate to the ESX host.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
