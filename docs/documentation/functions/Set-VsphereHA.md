# Set-VsphereHA

## Synopsis

Sets vSphere High Availability to enabled or disabled for a specified cluster.

## Syntax

### enable

```powershell
Set-VsphereHA [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String> [-enableHA] [<CommonParameters>]
```

### disable

```powershell
Set-VsphereHA [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String> [-disableHA] [<CommonParameters>]
```

## Description

The `Set-VsphereHA` cmdlet sets vSphere High Availability to enabled or disabled for a specified cluster.

## Examples

### Example 1

```powershell
Set-VsphereHA -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -enableHA
```

This example connects to a vCenter instance and sets the specified cluster in to a enabled/active vSphere High Availability state.

### Example 2

```powershell
Set-VsphereHA -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -cluster [cluster_name] -disableHA
```

This example connects to a vCenter instance and sets the specified cluster in to a disabled/stopped vSphere High Availability state.

## Parameters

### -server

The FQDN of the vCenter.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: Named
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
Position: Named
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
Position: Named
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
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -enableHA

The switch to enable vSphere High Availability.

```yaml
Type: SwitchParameter
Parameter Sets: enable
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -disableHA

The switch to disable vSphere High Availability.

```yaml
Type: SwitchParameter
Parameter Sets: disable
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
