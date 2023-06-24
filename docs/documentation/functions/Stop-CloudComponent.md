# Stop-CloudComponent

## Synopsis

Shuts down a node or nodes in a vCenter Server inventory.

## Syntax

### Node

```powershell
Stop-CloudComponent -server <String> -user <String> -pass <String> -timeout <Int32> [-noWait] -nodes <String[]> [<CommonParameters>]
```

### Pattern

```powershell
Stop-CloudComponent -server <String> -user <String> -pass <String> -timeout <Int32> [-noWait] -pattern <String[]> [<CommonParameters>]
```

## Description

The `Stop-CloudComponent` cmdlet shuts down a node or nodes in a vCenter Server inventory.

## Examples

### Example 1

```powershell
Stop-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02"
```

This example connects to a vCenter Server and shuts down the nodes sfo-m01-en01 and sfo-m01-en02.

### Example 2

```powershell
Stop-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user root -pass VMw@re1! -timeout 20 pattern "^vCLS.*"
```

This example connects to an ESXi Host and shuts down the nodes that match the pattern vCLS.*.

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
