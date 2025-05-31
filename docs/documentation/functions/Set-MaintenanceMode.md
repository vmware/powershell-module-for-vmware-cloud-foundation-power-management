# Set-MaintenanceMode

## Synopsis

Sets maintenance mode on an ESX host.

## Syntax

```powershell
Set-MaintenanceMode [-server] <String> [-user] <String> [-pass] <String> [-state] <String> [<CommonParameters>]
```

## Description

The `Set-MaintenanceMode` cmdlet enables or disables maintenance mode on an ESX host.

## Examples

### Example 1

```powershell
Set-MaintenanceMode -server [esx_fqdn] -user [admin_username] -pass [admin_password] -state [maintenance_mode_state]
```

This example places an ESX host in the specified maintenance mode state.

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

The username to authenticate to ESX host.

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

The password to authenticate to ESX host.

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

The state of the maintenance mode to be set on ESX host.
The value can be one of the following ("ENABLE" or "DISABLE").

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
