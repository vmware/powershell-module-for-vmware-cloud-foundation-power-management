# Get-TanzuEnabledClusterStatus

## Synopsis

Returns the Tanzu status of a specified cluster.

## Syntax

```powershell
Get-TanzuEnabledClusterStatus [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String> [<CommonParameters>]
```

## Description

The `Get-TanzuEnabledClusterStatus` checks if a specified cluster has Tanzu enabled.

## Examples

### Example 1

```powershell
Get-TanzuEnabledClusterStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name]
```

This example returns status (True/False) if the specified cluster has Tanzu enabled.

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

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
