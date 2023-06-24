# Set-MaintenanceMode

## Synopsis

Sets maintenance mode on an ESXi host.

## Syntax

```powershell
Set-MaintenanceMode [-server] <String> [-user] <String> [-pass] <String> [-state] <String> [<CommonParameters>]
```

## Description

The `Set-MaintenanceMode` cmdlet enables or disables maintenance mode on an ESXi host.

## Examples

### Example 1

```powershell
Set-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -state ENABLE
```

This example places an ESXi host in maintenance mode.

### Example 2

```powershell
Set-MaintenanceMode -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -state DISABLE
```

This example takes an ESXi host out of maintenance mode.

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

### -state

The state of the maintenance mode to be set on ESXi host.
Allowed states are "ENABLE" or "DISABLE".

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
