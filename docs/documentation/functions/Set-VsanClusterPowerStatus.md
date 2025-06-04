# Set-VsanClusterPowerStatus

## Synopsis

Set the power status of a vSAN cluster.

## Syntax

```powershell
Set-VsanClusterPowerStatus [-server] <String> [-user] <String> [-pass] <String> [-clustername] <String> [-mgmt] [-PowerStatus] <String> [<CommonParameters>]
```

## Description

The `Set-VsanClusterPowerStatus` cmdlet sets the power status of a vSAN cluster.

## Examples

### Example 1

```powershell
Set-VsanClusterPowerStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -PowerStatus [power_status]
```

This example connects to a vCenter instance and puts the specified cluster in a specified power status.

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

### -clustername

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

### -mgmt

The switch used to ignore power settings if management domain information is passed.

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

### -PowerStatus

The power state to be set for a given vSAN cluster.
The value can be one of the following ("clusterPoweredOff", "clusterPoweredOn").

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
