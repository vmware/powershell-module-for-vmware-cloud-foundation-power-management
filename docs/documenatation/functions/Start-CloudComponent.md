# Start-CloudComponent

## Synopsis

Starts up a node or nodes in a vCenter Server inventory.

## Syntax

### Node

```powershell
Start-CloudComponent -server <String> -user <String> -pass <String> -timeout <Int32> -nodes <String[]> [<CommonParameters>]
```

### Pattern

```powershell
Start-CloudComponent -server <String> -user <String> -pass <String> -timeout <Int32> -pattern <String[]> [<CommonParameters>]
```

## Description

The `Start-CloudComponent` cmdlet starts up a node or nodes in a vCenter Server inventory.

## Examples

### Example 1

```powershell
Start-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user adminstrator@vsphere.local -pass VMw@re1! -timeout 20 -nodes "sfo-m01-en01", "sfo-m01-en02"
```

This example connects to a vCenter Server and starts up the nodes sfo-m01-en01 and sfo-m01-en02.

### Example 2

```powershell
Start-CloudComponent -server sfo-m01-vc01.sfo.rainpole.io -user root -pass VMw@re1! -timeout 20 pattern "^vCLS.*"
```

This example connects to an ESXi Host and starts up the nodes that match the pattern vCLS.*.

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
