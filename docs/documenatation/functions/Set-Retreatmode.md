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
Set-Retreatmode -server $server -user $user -pass $pass -cluster $cluster -mode enable
```

This example places the vSphere Cluster virtual machines (vCLS) in the retreat mode.

### Example 2

```powershell
Set-Retreatmode -server $server -user $user -pass $pass -cluster $cluster -mode disable
```

This example takes places the vSphere Cluster Services (vCLS) virtual machines out of retreat mode.

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

### -mode

The name of the retreat mode.
The value is one amongst ("enable", "disable").

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
