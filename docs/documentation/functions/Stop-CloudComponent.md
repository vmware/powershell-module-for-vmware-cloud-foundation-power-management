# Stop-CloudComponent

## Synopsis

Shuts down a node or nodes in a vCenter inventory.

## Syntax

### Node

```powershell
Stop-CloudComponent [-server] <String> [-user] <String> [-pass] <String> [-timeout] <Int32> [-noWait] [-nodes] <String[]> [<CommonParameters>]
```

### Pattern

```powershell
Stop-CloudComponent [-server] <String> [-user] <String> [-pass] <String> [-timeout] <Int32> [-noWait] [-pattern] <String[]> [<CommonParameters>]
```

## Description

The `Stop-CloudComponent` cmdlet shuts down a node or nodes in a vCenter inventory.

## Examples

### Example 1

```powershell
Stop-CloudComponent -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -timeout [timeout_seconds] -nodes [node_name, node_name]
```

This example connects to a vCenter and shuts down the specified nodes after waiting the specified amount of seconds
for the cloud component to reach the desired state.

### Example 2

```powershell
Stop-CloudComponent -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -timeout [timeout_seconds] -pattern [cloud_component_pattern]
```

This example connects to a vCenter and shuts down the specified nodes which match the specified pattern after waiting
the specified amount of seconds for the cloud component to reach the desired state.

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

### -timeout

The timeout in seconds to wait for the cloud component to reach the desired connection state.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: True
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

### -noWait

To shudown the cloud component and not wait for desired connection state change.

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

### -nodes

The FQDNs of the list of cloud components to shutdown.

```yaml
Type: String[]
Parameter Sets: Node
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -pattern

The cloud components matching the pattern in the SDDC Manager inventory to be shutdown.

```yaml
Type: String[]
Parameter Sets: Pattern
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
