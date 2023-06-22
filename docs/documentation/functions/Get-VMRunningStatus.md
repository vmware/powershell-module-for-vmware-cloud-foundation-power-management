# Get-VMRunningStatus

## Synopsis

Returns the running status of a virtual machine.

## Syntax

```powershell
Get-VMRunningStatus [-server] <String> [-user] <String> [-pass] <String> [-pattern] <String> [[-Status] <String>] [<CommonParameters>]
```

## Description

The `Get-VMRunningStatus` cmdlet returns the running status of the given nodes matching the pattern on an ESXi host.

## Examples

### Example 1

```powershell
Get-VMRunningStatus -server sfo-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -pattern "^vCLS*"
```

This example connects to an ESXi host and searches for all virtual machines matching the pattern and gets their running status.

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

### -pattern

The pattern to match set of virtual machines.

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
The value can be one amongst ("Running", "NotRunning").
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
