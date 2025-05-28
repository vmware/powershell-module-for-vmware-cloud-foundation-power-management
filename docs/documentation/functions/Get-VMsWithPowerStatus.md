# Get-VMsWithPowerStatus

## Synopsis

Returns a list of virtual machines that are in a specified power state.

## Syntax

```powershell
Get-VMsWithPowerStatus [-server] <String> [-user] <String> [-pass] <String> [-powerstate] <String> [[-pattern] <String>] [-exactMatch] [-silence] [<CommonParameters>]
```

## Description

The `Get-VMsWithPowerStatus` cmdlet returns a list of virtual machines that are in a specified power state on a specified vCenter or ESX host.

## Examples

### Example 1

```powershell
Get-VMsWithPowerStatus -server [esx_fqdn] -user [admin_username] -pass [admin_password] -powerstate [power_state]
```

This example connects to the specified ESX host and returns the list of all powered on virtual machines.

### Example 2

```powershell
Get-VMsWithPowerStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -powerstate [power_state] -pattern [vm_name_pattern] -exactmatch
```

This example connects to a vCenter instance and returns a powered on VM with a specified name.

### Example 3

```powershell
Get-VMsWithPowerStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -powerstate [power_state] -pattern [vm_name_pattern]
```

This example connects to a vCenter instance and returns all powered on virtual machines matching the pattern.

### Example 4

```powershell
Get-VMsWithPowerStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -powerstate [power_state] -pattern [vm_name_pattern] -silence
```

This example connects to a vCenter instance and returns all powered on virtual machines matching the pattern and suppressing log messages in the output.

## Parameters

### -server

The FQDN of the vCenter.

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

The username to authenticate to vCenter.

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

The password to authenticate to vCenter.

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

### -powerstate

The power state of the virtual machines.
The values can be one of the following ("poweredon","poweredoff").

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

### -pattern

The pattern to match virtual machine names.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -exactMatch

The switch to match exact virtual machine name.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -silence

The switch to supress log messages.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
