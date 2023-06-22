# Get-TanzuEnabledClusterStatus

## Synopsis

Returns the Tanzu status of a cluster.

## Syntax

```powershell
Get-TanzuEnabledClusterStatus [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String> [<CommonParameters>]
```

## Description

The `Get-TanzuEnabledClusterStatus` checks if the given Cluster is Tanzu enabled.

## Examples

### Example 1

```powershell
Get-TanzuEnabledClusterStatus -server $server -user $user -pass $pass -cluster $cluster
```

This example returns True if the given cluster is Tanzu enabled else false.

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
