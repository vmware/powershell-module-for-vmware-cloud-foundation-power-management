# Get-VMToClusterMapping

## Synopsis

Returns a list of all virtual machines that are running on a cluster.

## Syntax

```powershell
Get-VMToClusterMapping [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String[]> [-folder] <String> [-silence] [[-powerstate] <String>] [<CommonParameters>]
```

## Description

The `Get-VMToClusterMapping` cmdlet returns a list of all virtual machines that are running on a specified cluster.

## Examples

### Example 1

```powershell
Get-VMToClusterMapping -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -folder [folder_name]
```

This example returns all virtual machines in a specified folder on a specified cluster.

### Example 2

```powershell
Get-VMToClusterMapping -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -folder [folder_name] -powerstate [power_state]
```

This example returns only the virtual machines in a specified folder on a specified cluster for a specified power state.

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
Type: String[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -folder

The name of the folder to search for virtual machines.

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

### -powerstate

The powerstate of the virtual machines.
The value can be one of the following ("poweredon","poweredoff").

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
