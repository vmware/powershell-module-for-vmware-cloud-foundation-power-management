# Wait-ForStableNsxtClusterStatus

## Synopsis

Returns the cluster status of an NSX Manager after a restart.

## Syntax

```powershell
Wait-ForStableNsxtClusterStatus [-server] <String> [-user] <String> [-pass] <String> [<CommonParameters>]
```

## Description

The `Wait-ForStableNsxtClusterStatus` cmdlet returns the cluster status of an NSX manager after a restart.

## Examples

### Example 1

```powershell
Wait-ForStableNsxtClusterStatus -server sfo-m01-nsx01.sfo.rainpole.io -user admin -pass VMw@re1!VMw@re1!
```

This example gets the cluster status of the sfo-m01-nsx01.sfo.rainpole.io NSX Management Cluster.

## Parameters

### -server

The FQDN of the NSX Manager.

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

The username to authenticate to NSX Manager.

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

The password to authenticate to NSX Manager.

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

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
