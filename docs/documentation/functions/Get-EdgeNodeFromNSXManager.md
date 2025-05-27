# Get-EdgeNodeFromNSXManager

## Synopsis

Returns a list of NSX Edge nodes from NSX.

## Syntax

```powershell
Get-EdgeNodeFromNSXManager [-server] <String> [-user] <String> [-pass] <String> [[-VCfqdn] <String>] [<CommonParameters>]
```

## Description

The `Get-EdgeNodeFromNSXManager` cmdlet returns a list of NSX Edge nodes from NSX.

## Examples

### Example 1

```powershell
Get-EdgeNodeFromNSXManager -server [nsx_fqdn] -user [admin_username] -pass [admin_password]
```

This example returns a list of NSX Edge nodes from NSX.

### Example 2

```powershell
Get-EdgeNodeFromNSXManager -server [nsx_fqdn] -user [admin_username] -pass [admin_password] -VCfqdn [vcenter_fqdn]
```

This example returns a list of NSX Edge nodes from a specified vCenter.

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

The username to authenticate to the NSX Manager.

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

The password to authenticate to the NSX Manager.

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

### -VCfqdn

The FQDN of the vCenter.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
