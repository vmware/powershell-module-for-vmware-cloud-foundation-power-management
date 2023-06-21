# Get-SSHEnabledStatus

## Synopsis

Returns the SSH status on an ESXi host.

## Syntax

```powershell
Get-SSHEnabledStatus [-server] <String> [-user] <String> [-pass] <String> [<CommonParameters>]
```

## Description

The `Get-SSHEnabledStatus` cmdlet creates a new SSH session to the given host to see if SSH is enabled. It returns true if SSH enabled.

## Examples

### Example 1

```powershell
Get-SSHEnabledStatus -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1!
```

This example checks if SSH is enabled on the given host.

## Parameters

### -server

The FQDN of the ESXi host.

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

The username to authenticate to ESXi host.

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

The password to authenticate to ESXi host.

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
