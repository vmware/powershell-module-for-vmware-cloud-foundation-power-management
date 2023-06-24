# Get-VMsWithPowerStatus

## Synopsis

Returns a list of virtual machines that are in a specified power state.

## Syntax

```powershell
Get-VMsWithPowerStatus [-server] <String> [-user] <String> [-pass] <String> [-powerstate] <String> [[-pattern] <String>] [-exactMatch] [-silence] [<CommonParameters>]
```

## Description

The `Get-VMsWithPowerStatus` cmdlet returns a list of virtual machines that are in a specified power state on a specified vCenter Server or ESXi host.

## Examples

### Example 1

```powershell
Get-VMsWithPowerStatus -server sfo01-m01-esx01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -powerstate "poweredon"
```

This example connects to an ESXi host and returns the list of powered-on virtual machines.

### Example 2

```powershell
Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user <administrator@vsphere.local> -pass VMw@re1! -powerstate "poweredon" -pattern "sfo-wsa01" -exactmatch
```

This example connects to a vCenter Server instance and returns a powered-on VM with name sfo-wsa01.

### Example 3

```powershell
Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user <administrator@vsphere.local> -pass VMw@re1! -powerstate "poweredon" -pattern "vcls"
```

This example connects to a vCenter Server instance and returns the list of powered-on vCLS virtual machines.

### Example 4

```powershell
Get-VMsWithPowerStatus -server sfo-m01-vc01.sfo.rainpole.io -user <administrator@vsphere.local> -pass VMw@re1! -powerstate "poweredon" -pattern "vcls" -silence
```

This example connects to a vCenter Server instance and returns the list of powered-on vCLS virtual machines without log messages in the output.

## Parameters

### -server

The FQDN of the vCenter Server.

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

The username to authenticate to vCenter Server.

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

The password to authenticate to vCenter Server.

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

The powerstate of the virtual machines.
The values can be one amongst ("poweredon","poweredoff").

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

The switch to supress selected log messages.

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
