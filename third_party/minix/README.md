# Minix 1.5 demonstration diskette

`demo_dsk.ibm` is the 360K demonstration diskette of Minix 1.5 for the IBM
PC ("Booting MINIX 1.5. Copyright 1991 Prentice-Hall, Inc."), a raw sector
image, 368,640 bytes, unmodified:

```
sha256 98d11c9ff30dbf31cb8ffda786de7892a6ebdbfac5ebb913724cbe78e30fb48a
```

Minix is distributed under the BSD-style licence in `LICENSE`, which
Prentice Hall agreed to in April 2000.

XT/GS boots it (`make run-minix`, `make test-minix`; `docs/minix.md`). It
holds a boot block, the kernel, memory manager, file system and `init`, and
a 192K root file system that Minix loads into a RAM disk: a shell and 25
commands. Log in as `root`.
