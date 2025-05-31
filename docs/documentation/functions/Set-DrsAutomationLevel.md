# Set-DrsAutomationLevel

## Synopsis

Sets the vSphere Distributed Resource Scheduler automation level.

## Syntax

```powershell
Set-DrsAutomationLevel [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String> [-level] <String> [<CommonParameters>]
```

## Description

The `Set-DrsAutomationLevel` cmdlet sets the automation level of the cluster based on the setting provided.

## Examples

### Example 1

```powershell
Set-DrsAutomationLevel -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -level [drs_level]
```

This example sets the vSphere Distributed Resource Scheduler Automation level for the specified cluster to the specified DRS level.

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

### -cluster

The name of the cluster on which the vSphere Distributed Resource Scheduler automation level settings are to be applied.

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

### -level

The vSphere Distributed Resource Scheduler automation level to be set.
The value can be one of the following ("FullyAutomated", "Manual", "PartiallyAutomated", "Disabled").

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
