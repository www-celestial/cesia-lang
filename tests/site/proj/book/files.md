# Files

## Reading

```cesia allow=read
use std/sys
Print(sys.Read("notes.txt").Value)
```

A block that stops can repeat a use of the page:

```cesia fails
use std/sys
sys.Write("notes.txt", "no")
```

Back to [the start](index.md).
