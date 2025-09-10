# Multi Mounter - file-system mounter (Supports Retro Disk and HD images)
X-Seti - Sept 10 2025 - MultiMount - Universal Filesystem Mount Script - Handles various filesystem types and mounting scenarios

Deps: pipx install amitools

"pacaur -S", "apt install" or "dnf install"

xdms vice hatari nulib2 adf-utils vim xxd applecommander steem trstool xtrs

Usage: ./multimount.sh [OPTIONS] <filesystem_image>

Options:

  -m, --mount-point PATH    Mount point (default: /mnt/auto-mount)
  
  -r, --ramdisk SIZE        Create ramdisk of SIZE (e.g., 2G, 512M)
  
  -t, --type TYPE           Force filesystem type
  
  -u, --umount             Unmount specified path
  
  -l, --list               List all loop devices
  
  -c, --check              Only check file type, don't mount
  
  -v, --verbose            Verbose output
  
  -i, --install-retro      Install retro computer filesystem tools
  
  -h, --help               Show this help


Supported formats:
  AMIGA: ADF, HDF, DMS, ADZ (OFS/FFS/PFS/SFS filesystems)

  APPLE II: DSK, DO, PO, 2MG, NIB, WOZ, HDV, D13
  
  ATARI: ST, MSA, STX, DIM, IPF, ATR (Atari ST & 8-bit)
  
  TRS-80: JV1, JV3, DMK (Model I/III/4)
  
  COMMODORE: D64, D71, D81, T64, PRG, P00, G64
  
  GENERAL: SquashFS, ISO9660, EXT2/3/4, XFS, BTRFS

Examples:
  
  ./multimount.sh /path/to/image.squashfs
  
  ./multimount.sh -m /tmp/mount /path/to/image.iso
  
  ./multimount.sh /path/to/game.adf
  
  ./multimount.sh /path/to/apple_disk.dsk
  
  ./multimount.sh /path/to/atari_disk.st
  
  ./multimount.sh /path/to/trs80_disk.dmk
  
  ./multimount.sh /path/to/c64_disk.d64
  
  ./multimount.sh /path/to/workbench.hdf
  
  ./multimount.sh -r 2G -m /tmp/ramdisk
  ./multimount.sh -u /mnt/auto-mount
  ./multimount.sh -c /path/to/unknown_image
  ./multimount.sh -i  # Install retro computer tools
