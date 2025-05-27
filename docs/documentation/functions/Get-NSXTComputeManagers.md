# Get-NSXTComputeManagers

## Synopsis

Returns the list of all NSX Compute Managers connected to NSX.

## Syntax

```powershell
Get-NSXTComputeManagers [-server] <String> [-user] <String> [-pass] <String> [<CommonParameters>]
```

## Description

The `Get-NSXTComputeManagers` cmdlet returns the list of all NSX Compute Managers connected to NSX.

## Examples

### Example 1

```powershell
Get-NSXTComputeManagers -server [nsx_fqdn] -user [admin_username] -pass [admin_password]
```

This example returns the list of all NSX Compute Managers connected to NSX.

## Parameters

### -server

The FQDN of the NSX Manager.

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

The username to authenticate to NSX Manager.

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

The password to authenticate to NSX Manager.

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
