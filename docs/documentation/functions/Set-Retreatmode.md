# Set-Retreatmode

## Synopsis

Sets retreat mode for vSphere Cluster Services (vCLS) virtual machines on a cluster.

## Syntax

```powershell
Set-Retreatmode [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String> [-mode] <String> [<CommonParameters>]
```

## Description

The `Set-Retreatmode` cmdlet enables or disables retreat mode for the vSphere Cluster Services (vCLS) virtual machines.

## Examples

### Example 1

```powershell
Set-Retreatmode -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -mode [retreat_mode]
```

This example places the vSphere Cluster virtual machines (vCLS) in the specified retreat mode in a specified cluster.

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

The name of the cluster.

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

### -mode

The name of the retreat mode.
The value can be one of the following ("enable", "disable").

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
