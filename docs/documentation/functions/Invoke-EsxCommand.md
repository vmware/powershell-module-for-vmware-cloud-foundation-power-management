# Invoke-EsxCommand

## Synopsis

Runs a specified command on an ESX host.

## Syntax

```powershell
Invoke-EsxCommand [-server] <String> [-user] <String> [-pass] <String> [-cmd] <String> [[-expected] <String>] [<CommonParameters>]
```

## Description

The `Invoke-EsxCommand` cmdlet runs a specified command on an ESX host.

If the expected flag is not passed into the command, then the exit status of 0 is considered as success.

## Examples

### Example 1

```powershell
Invoke-EsxCommand -server [esx_fqdn] -user [admin_username] -pass [admin_password] -expected [expected_output] -cmd [esx_command]
```

This example connects to an ESX host and runs a specified command and provides a specified output, to check against.

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

### -cmd

The command to be exectued on the ESX host.

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

The expected output to be compared against the output returned from the command execution.

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
