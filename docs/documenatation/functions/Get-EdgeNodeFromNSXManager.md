# Get-EdgeNodeFromNSXManager

## Synopsis

Returns list of edge nodes virtual machines names from NSX Manager.

## Syntax

```powershell
Get-EdgeNodeFromNSXManager [-server] <String> [-user] <String> [-pass] <String> [[-VCfqdn] <String>] [<CommonParameters>]
```

## Description

The `Get-EdgeNodeFromNSXManager` used to read edge node virtual machine names from NSX manager.

## Examples

### Example 1

```powershell
Get-EdgeNodeFromNSXManager -server $server -user $user -pass $pass
```

This example returns list of edge nodes virtual machines name.

### Example 2

```powershell
Get-EdgeNodeFromNSXManager -server $server -user $user -pass $pass -VCfqdn $VCfqdn
```

This example returns list of edge nodes virtual machines name from a given virtual center only.

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

### -VCfqdn

The FQDN of the vCenter Server.

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
