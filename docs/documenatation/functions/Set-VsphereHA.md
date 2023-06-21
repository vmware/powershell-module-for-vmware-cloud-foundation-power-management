# Set-VsphereHA

## Synopsis

Sets vSphere High Availability to enabled or disabled for a cluster.

## Syntax

### enable

```powershell
Set-VsphereHA -server <String> -user <String> -pass <String> -cluster <String> [-enableHA] [<CommonParameters>]
```

### disable

```powershell
Set-VsphereHA -server <String> -user <String> -pass <String> -cluster <String> [-disableHA] [<CommonParameters>]
```

## Description

The `Set-VsphereHA` cmdlet sets vSphere High Availability to enabled or disabled for a cluster.

## Examples

### Example 1

```powershell
Set-VsphereHA -server $server -user $user -pass $pass -cluster $cluster -enable
```

This example sets vSphere High Availability to enabled/active.

### Example 2

```powershell
Set-VsphereHA -server $server -user $user -pass $pass -cluster $cluster -disable
```

This example sets vSphere High Availability to disabled/stopped.

## Parameters

### -server

The FQDN of the vCenter Server.

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

The username to authenticate to vCenter Server.

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

The password to authenticate to vCenter Server.

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
