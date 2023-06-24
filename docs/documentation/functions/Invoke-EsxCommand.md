# Invoke-EsxCommand

## Synopsis

Runs a provided command on an ESXi host.

## Syntax

```powershell
Invoke-EsxCommand [-server] <String> [-user] <String> [-pass] <String> [-cmd] <String> [[-expected] <String>] [<CommonParameters>]
```

## Description

The `Invoke-EsxCommand` cmdlet runs a command on an ESXi host.

If expected is not passed, then #exitstatus of 0 is considered as success.

## Examples

### Example 1

```powershell
Invoke-EsxCommand -server sfo01-w01-esx01.sfo.rainpole.io -user root -pass VMw@re1! -expected "Value of IgnoreClusterMemberListUpdates is 1" -cmd "esxcfg-advcfg -s 0 /VSAN/IgnoreClusterMemberListUpdates"
```

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

### -cmd

The command to be exectued on the ESXi host.

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

### -expected

The expected output to be compared against output returned from the command execution.

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

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
