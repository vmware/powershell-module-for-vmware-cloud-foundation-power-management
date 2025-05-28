# Get-VMRunningStatus

## Synopsis

Returns the status of virtual machines with a specified pattern in the VM name.

## Syntax

```powershell
Get-VMRunningStatus [-server] <String> [-user] <String> [-pass] <String> [-pattern] <String> [[-Status] <String>] [<CommonParameters>]
```

## Description

The `Get-VMRunningStatus` cmdlet returns the status of virtual machines with a specified pattern in the VM name on a specified ESX host.

## Examples

### Example 1

```powershell
Get-VMRunningStatus -server [esx_fqdn] -user [admin_username] -pass [admin_password] -pattern [vm_name_pattern]
```

This example connects to an ESX host and searches for all virtual machines matching the pattern and gets their running status.

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

### -pattern

The pattern to match a set of virtual machines.

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

### -Status

The state of the virtual machine to be tested against.
The value can be one of the following ("Running", "NotRunning").
The default value is "Running".

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: Running
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
