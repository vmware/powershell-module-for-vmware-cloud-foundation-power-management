# Start-CloudComponent

## Synopsis

Starts up a node or nodes in a vCenter inventory.

## Syntax

### Node

```powershell
Start-CloudComponent [-server] <String> [-user] <String> [-pass] <String> [-timeout] <Int32> [-nodes] <String[]> [<CommonParameters>]
```

### Pattern

```powershell
Start-CloudComponent [-server] <String> [-user] <String> [-pass] <String> [-timeout] <Int32> [-pattern] <String[]> [<CommonParameters>]
```

## Description

The `Start-CloudComponent` cmdlet starts up a node or nodes in a vCenter inventory.

## Examples

### Example 1

```powershell
Start-CloudComponent -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -timeout [timeout_seconds] -nodes [node_name, node_name]
```

This example connects to a vCenter and starts up the specified nodes after waiting the specified amount of seconds
for the cloud component to reach the desired state.

### Example 2

```powershell
Start-CloudComponent -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -timeout [timeout_seconds] -pattern [cloud_component_pattern]
```

This example connects to a vCenter and starts up the specified nodes which match the specified pattern after waiting
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

### -nodes

The FQDNs of the list of cloud components to startup.

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

The cloud components matching the pattern in the SDDC Manager inventory to be startup.

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
