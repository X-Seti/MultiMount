#!/bin/bash

# X-Seti - Sept 10 2025 - MultiMount - Version 5
# Universal Filesystem Mount Script
# Handles various filesystem types and mounting scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default mount point
DEFAULT_MOUNT="/mnt/auto-mount"

usage() {
    echo -e "${BLUE}Universal Filesystem Mount Script${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS] <filesystem_image>"
    echo ""
    echo "Options:"
    echo "  -m, --mount-point PATH    Mount point (default: $DEFAULT_MOUNT)"
    echo "  -r, --ramdisk SIZE        Create ramdisk of SIZE (e.g., 2G, 512M)"
    echo "  -t, --type TYPE           Force filesystem type"
    echo "  -u, --umount             Unmount specified path"
    echo "  -l, --list               List all loop devices"
    echo "  -c, --check              Only check file type, don't mount"
    echo "  -v, --verbose            Verbose output"
    echo "  -i, --install-retro      Install retro computer filesystem tools"
    echo "  -h, --help               Show this help"
    echo ""
    echo "Supported formats:"
    echo "  AMIGA: ADF, HDF, DMS, ADZ (OFS/FFS/PFS/SFS filesystems)"
    echo "  APPLE II: DSK, DO, PO, 2MG, NIB, WOZ, HDV, D13"
    echo "  ATARI: ST, MSA, STX, DIM, IPF, ATR (Atari ST & 8-bit)"
    echo "  TRS-80: JV1, JV3, DMK (Model I/III/4)"
    echo "  COMMODORE: D64, D71, D81, T64, PRG, P00, G64"
    echo "  GENERAL: SquashFS, ISO9660, EXT2/3/4, XFS, BTRFS"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/image.squashfs"
    echo "  $0 -m /tmp/mount /path/to/image.iso"
    echo "  $0 /path/to/game.adf"
    echo "  $0 /path/to/apple_disk.dsk"
    echo "  $0 /path/to/atari_disk.st"
    echo "  $0 /path/to/trs80_disk.dmk"
    echo "  $0 /path/to/c64_disk.d64"
    echo "  $0 /path/to/workbench.hdf"
    echo "  $0 -r 2G -m /tmp/ramdisk"
    echo "  $0 -u /mnt/auto-mount"
    echo "  $0 -c /path/to/unknown_image"
    echo "  $0 -i  # Install retro computer tools"
}

log() {
    if [[ $VERBOSE == true ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_filesystem() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        error "File not found: $file_path"
        return 1
    fi

    echo -e "${BLUE}Analyzing filesystem:${NC} $file_path"

    # Get file info
    local file_info=$(file "$file_path")
    echo "File type: $file_info"

    # Get size
    local size=$(du -h "$file_path" | cut -f1)
    echo "Size: $size"

    # Check magic bytes for common formats
    local magic=$(hexdump -C "$file_path" | head -1)
    echo "Magic bytes: $magic"

    # Get first few bytes for Amiga detection
    local first_bytes=$(xxd -l 16 "$file_path" 2>/dev/null | head -1)
    echo "First 16 bytes: $first_bytes"

    # Determine filesystem type
    if [[ $file_info == *"Squashfs"* ]]; then
        echo -e "${GREEN}Detected: SquashFS${NC}"
        return 0
    elif [[ $file_info == *"ISO 9660"* ]]; then
        echo -e "${GREEN}Detected: ISO 9660${NC}"
        return 0
    elif [[ $file_info == *"ext2"* ]] || [[ $file_info == *"ext3"* ]] || [[ $file_info == *"ext4"* ]]; then
        echo -e "${GREEN}Detected: EXT filesystem${NC}"
        return 0
    elif [[ $file_info == *"XFS"* ]]; then
        echo -e "${GREEN}Detected: XFS${NC}"
        return 0
    elif [[ $file_info == *"BTRFS"* ]]; then
        echo -e "${GREEN}Detected: BTRFS${NC}"
        return 0
    elif check_amiga_filesystem "$file_path"; then
        return 0
    elif check_apple_filesystem "$file_path"; then
        return 0
    elif check_atari_filesystem "$file_path"; then
        return 0
    elif check_trs80_filesystem "$file_path"; then
        return 0
    elif check_commodore_filesystem "$file_path"; then
        return 0
    else
        warn "Unknown or unsupported filesystem type"
        return 1
    fi
}

check_amiga_filesystem() {
    local file_path="$1"

    # Check for Amiga filesystem signatures
    # Read first 512 bytes to check boot block
    local bootblock=$(xxd -l 512 "$file_path" 2>/dev/null)

    # Check for OFS/FFS signatures
    # OFS/FFS boot blocks often start with specific patterns
    if echo "$bootblock" | grep -q "444f5300\|444f5301\|444f5302\|444f5303"; then
        echo -e "${GREEN}Detected: Amiga OFS/FFS (DOS\\0, DOS\\1, DOS\\2, DOS\\3)${NC}"
        return 0
    fi

    # Check for PFS signature (Professional File System)
    # PFS has "PFS\\" signature at specific offsets
    if echo "$bootblock" | grep -q "50465300"; then
        echo -e "${GREEN}Detected: Amiga PFS (Professional File System)${NC}"
        return 0
    fi

    # Check for SFS signature (Smart File System)
    if echo "$bootblock" | grep -q "53465300"; then
        echo -e "${GREEN}Detected: Amiga SFS (Smart File System)${NC}"
        return 0
    fi

    # Check for AFFS signature (Amiga Fast File System)
    if echo "$bootblock" | grep -q "41464653"; then
        echo -e "${GREEN}Detected: Amiga AFFS${NC}"
        return 0
    fi

    # Check ADF signature (Amiga Disk File)
    # ADF files are raw disk images, check size (880KB for DD, 1760KB for HD)
    local size_bytes=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
    if [[ $size_bytes -eq 901120 ]] || [[ $size_bytes -eq 1802240 ]]; then
        echo -e "${GREEN}Detected: Amiga ADF (Disk Image)${NC}"
        echo "  Size suggests: $([ $size_bytes -eq 901120 ] && echo "DD (880KB)" || echo "HD (1760KB)") floppy"
        return 0
    fi

    # Check for HDF (Hard Disk File) - larger Amiga disk images
    if [[ $size_bytes -gt 1802240 ]] && echo "$bootblock" | grep -q "444f53"; then
        echo -e "${GREEN}Detected: Amiga HDF (Hard Disk File)${NC}"
        return 0
    fi

    # Check for common Amiga file extensions
    local filename=$(basename "$file_path")
    case "${filename,,}" in
        *.adf)
            echo -e "${GREEN}Detected: Amiga ADF by extension${NC}"
            return 0
            ;;
        *.hdf)
            echo -e "${GREEN}Detected: Amiga HDF by extension${NC}"
            return 0
            ;;
        *.dms)
            echo -e "${GREEN}Detected: Amiga DMS (Disk Masher)${NC}"
            return 0
            ;;
        *.adz)
            echo -e "${GREEN}Detected: Amiga ADZ (Compressed ADF)${NC}"
            return 0
            ;;
    esac

    return 1
}

check_apple_filesystem() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local size_bytes=$(stat -c%s "$file_path" 2>/dev/null || echo 0)

    # Check for Apple II disk image signatures and sizes
    # Standard Apple II 5.25" disk: 143,360 bytes (35 tracks × 16 sectors × 256 bytes)
    if [[ $size_bytes -eq 143360 ]]; then
        echo -e "${GREEN}Detected: Apple II 5.25\" disk image (140KB)${NC}"
        return 0
    fi

    # Apple II 3.5" disk: 819,200 bytes (800KB)
    if [[ $size_bytes -eq 819200 ]]; then
        echo -e "${GREEN}Detected: Apple II 3.5\" disk image (800KB)${NC}"
        return 0
    fi

    # Check by file extension
    case "${filename,,}" in
        *.dsk|*.do|*.po)
            echo -e "${GREEN}Detected: Apple II DSK/DO/PO disk image${NC}"
            return 0
            ;;
        *.2mg|*.2img)
            echo -e "${GREEN}Detected: Apple II 2MG disk image${NC}"
            return 0
            ;;
        *.nib)
            echo -e "${GREEN}Detected: Apple II NIB (Nibble) image${NC}"
            return 0
            ;;
        *.woz)
            echo -e "${GREEN}Detected: Apple II WOZ disk image${NC}"
            return 0
            ;;
        *.hdv)
            echo -e "${GREEN}Detected: Apple II HDV hard disk image${NC}"
            return 0
            ;;
        *.d13)
            echo -e "${GREEN}Detected: Apple II 13-sector disk image${NC}"
            return 0
            ;;
    esac

    # Check for 2MG header signature
    local header=$(xxd -l 8 "$file_path" 2>/dev/null | head -1)
    if echo "$header" | grep -q "32494d47"; then  # "2IMG"
        echo -e "${GREEN}Detected: Apple II 2MG by header signature${NC}"
        return 0
    fi

    return 1
}

check_atari_filesystem() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local size_bytes=$(stat -c%s "$file_path" 2>/dev/null || echo 0)

    # Standard Atari ST 3.5" disk sizes
    # 720KB (DD): 737,280 bytes
    # 1.44MB (HD): 1,474,560 bytes
    if [[ $size_bytes -eq 737280 ]]; then
        echo -e "${GREEN}Detected: Atari ST 720KB disk image${NC}"
        return 0
    elif [[ $size_bytes -eq 1474560 ]]; then
        echo -e "${GREEN}Detected: Atari ST 1.44MB disk image${NC}"
        return 0
    fi

    # Check by file extension
    case "${filename,,}" in
        *.st)
            echo -e "${GREEN}Detected: Atari ST raw disk image${NC}"
            return 0
            ;;
        *.msa)
            echo -e "${GREEN}Detected: Atari ST MSA (Magic Shadow Archiver)${NC}"
            return 0
            ;;
        *.stx)
            echo -e "${GREEN}Detected: Atari ST STX (Pasti format)${NC}"
            return 0
            ;;
        *.dim)
            echo -e "${GREEN}Detected: Atari ST DIM (Disk Image)${NC}"
            return 0
            ;;
        *.ipf)
            echo -e "${GREEN}Detected: Atari ST IPF (SPS format)${NC}"
            return 0
            ;;
        *.atr)
            echo -e "${GREEN}Detected: Atari 8-bit ATR disk image${NC}"
            return 0
            ;;
    esac

    # Check for MSA header (Magic Shadow Archiver)
    local header=$(xxd -l 4 "$file_path" 2>/dev/null | head -1)
    if echo "$header" | grep -q "0e0f"; then
        echo -e "${GREEN}Detected: Atari ST MSA by header${NC}"
        return 0
    fi

    return 1
}

check_trs80_filesystem() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local size_bytes=$(stat -c%s "$file_path" 2>/dev/null || echo 0)

    # Check for TRS-80 specific extensions first
    case "${filename,,}" in
        *.jv1|*.jv3)
            echo -e "${GREEN}Detected: TRS-80 JV1/JV3 disk image${NC}"
            return 0
            ;;
        *.dmk)
            echo -e "${GREEN}Detected: TRS-80 DMK disk image${NC}"
            return 0
            ;;
    esac

    # Check for DMK header signature (16-byte header)
    if [[ $size_bytes -gt 16 ]]; then
        local dmk_header=$(xxd -l 16 "$file_path" 2>/dev/null)
        # DMK files have specific header structure
        if echo "$dmk_header" | grep -q "00.*[0-9a-f][0-9a-f].*28\|50"; then
            echo -e "${GREEN}Detected: TRS-80 DMK by header structure${NC}"
            return 0
        fi
    fi

    # JV1 format: 35 tracks × 10 sectors × 256 bytes = 89,600 bytes
    if [[ $size_bytes -eq 89600 ]]; then
        echo -e "${GREEN}Detected: TRS-80 JV1 by size (35 track)${NC}"
        return 0
    fi

    # Check for other common TRS-80 sizes
    # 40 track JV1: 102,400 bytes
    if [[ $size_bytes -eq 102400 ]]; then
        echo -e "${GREEN}Detected: TRS-80 JV1 by size (40 track)${NC}"
        return 0
    fi

    return 1
}

check_commodore_filesystem() {
    local file_path="$1"
    local filename=$(basename "$file_path")
    local size_bytes=$(stat -c%s "$file_path" 2>/dev/null || echo 0)

    # Check by file extension
    case "${filename,,}" in
        *.d64)
            echo -e "${GREEN}Detected: Commodore 64 D64 disk image${NC}"
            return 0
            ;;
        *.d71)
            echo -e "${GREEN}Detected: Commodore 64 D71 disk image${NC}"
            return 0
            ;;
        *.d81)
            echo -e "${GREEN}Detected: Commodore 64 D81 disk image${NC}"
            return 0
            ;;
        *.d80|*.d82)
            echo -e "${GREEN}Detected: Commodore 8000/8050 disk image${NC}"
            return 0
            ;;
        *.t64)
            echo -e "${GREEN}Detected: Commodore 64 T64 tape image${NC}"
            return 0
            ;;
        *.prg)
            echo -e "${GREEN}Detected: Commodore PRG file${NC}"
            return 0
            ;;
        *.p00)
            echo -e "${GREEN}Detected: Commodore PC64 P00 file${NC}"
            return 0
            ;;
        *.g64)
            echo -e "${GREEN}Detected: Commodore 64 G64 GCR image${NC}"
            return 0
            ;;
    esac

    # Check by size for standard Commodore formats
    # D64: 174,848 bytes (35 tracks, standard)
    if [[ $size_bytes -eq 174848 ]]; then
        echo -e "${GREEN}Detected: Commodore D64 by size${NC}"
        return 0
    fi

    # D71: 349,696 bytes (double-sided D64)
    if [[ $size_bytes -eq 349696 ]]; then
        echo -e "${GREEN}Detected: Commodore D71 by size${NC}"
        return 0
    fi

    # D81: 819,200 bytes (3.5" disk)
    if [[ $size_bytes -eq 819200 ]]; then
        echo -e "${GREEN}Detected: Commodore D81 by size${NC}"
        return 0
    fi

    return 1
}

check_dependencies() {
    local missing_deps=()

    # Check for required tools
    if ! command -v xxd &> /dev/null; then
        missing_deps+=("xxd (vim-common package)")
    fi

    # Check for Amiga filesystem tools
    if ! command -v xdftool &> /dev/null && ! command -v unadf &> /dev/null; then
        warn "Amiga ADF tools not found. Install with: pip3 install amitools"
    fi

    if ! command -v xdftool &> /dev/null; then
        warn "xdftool not found. For Amiga HDF support: pip3 install amitools"
    fi

    # Check for Apple II tools
    if ! command -v ac &> /dev/null && ! command -v applecommander &> /dev/null; then
        warn "Apple II tools not found. Install AppleCommander or CiderPress"
    fi

    # Check for Atari tools
    if ! command -v msa &> /dev/null; then
        warn "Atari MSA tools not found. Consider installing Hatari or STeem"
    fi

    # Check for TRS-80 tools
    if ! command -v trsread &> /dev/null; then
        warn "TRS-80 tools not found. Install TRSTools or xtrs utilities"
    fi

    # Check for Commodore tools
    if ! command -v c1541 &> /dev/null; then
        warn "Commodore tools not found. Install: sudo apt install vice"
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies:"
        printf '%s\n' "${missing_deps[@]}"
        exit 1
    fi
}

create_ramdisk() {
    local size="$1"
    local mount_point="$2"

    log "Creating ramdisk of size $size at $mount_point"

    mkdir -p "$mount_point"
    mount -t tmpfs -o size="$size" tmpfs "$mount_point"

    echo -e "${GREEN}Ramdisk created successfully${NC}"
    echo "Mount point: $mount_point"
    echo "Size: $size"
    df -h "$mount_point"
}

mount_squashfs() {
    local file_path="$1"
    local mount_point="$2"

    log "Mounting SquashFS: $file_path -> $mount_point"

    mkdir -p "$mount_point"

    # Try different mount methods
    if mount -t squashfs -o loop "$file_path" "$mount_point" 2>/dev/null; then
        echo -e "${GREEN}Successfully mounted SquashFS${NC}"
        return 0
    elif mount -o loop "$file_path" "$mount_point" 2>/dev/null; then
        echo -e "${GREEN}Successfully mounted with auto-detection${NC}"
        return 0
    else
        error "Failed to mount SquashFS"
        return 1
    fi
}

mount_iso() {
    local file_path="$1"
    local mount_point="$2"

    log "Mounting ISO: $file_path -> $mount_point"

    mkdir -p "$mount_point"

    if mount -t iso9660 -o loop,ro "$file_path" "$mount_point" 2>/dev/null; then
        echo -e "${GREEN}Successfully mounted ISO${NC}"
        return 0
    elif mount -o loop,ro "$file_path" "$mount_point" 2>/dev/null; then
        echo -e "${GREEN}Successfully mounted with auto-detection${NC}"
        return 0
    else
        error "Failed to mount ISO"
        return 1
    fi
}

mount_generic() {
    local file_path="$1"
    local mount_point="$2"
    local fs_type="$3"

    log "Mounting $fs_type: $file_path -> $mount_point"

    mkdir -p "$mount_point"

    if [[ -n "$fs_type" ]]; then
        mount -t "$fs_type" -o loop "$file_path" "$mount_point"
    else
        mount -o loop "$file_path" "$mount_point"
    fi
}

mount_amiga_adf() {
    local file_path="$1"
    local mount_point="$2"

    log "Mounting Amiga ADF: $file_path -> $mount_point"

    mkdir -p "$mount_point"

    # Method 1: Try with adf-util (if available)
    if command -v adf-util &> /dev/null; then
        log "Using adf-util for ADF mounting"
        if adf-util -m "$file_path" "$mount_point" 2>/dev/null; then
            echo -e "${GREEN}Successfully mounted ADF with adf-util${NC}"
            return 0
        fi
    fi

    # Method 2: Try with unadf to extract (read-only)
    if command -v unadf &> /dev/null; then
        log "Using unadf to extract ADF contents"
        if unadf -x "$file_path" -d "$mount_point" 2>/dev/null; then
            echo -e "${GREEN}Successfully extracted ADF contents${NC}"
            echo -e "${YELLOW}Note: This is read-only extraction, not a mount${NC}"
            return 0
        fi
    fi

    # Method 3: Try loop mount with AFFS (if kernel supports it)
    if grep -q affs /proc/filesystems 2>/dev/null; then
        log "Attempting AFFS loop mount"
        if mount -t affs -o loop,ro "$file_path" "$mount_point" 2>/dev/null; then
            echo -e "${GREEN}Successfully mounted ADF with AFFS${NC}"
            return 0
        fi
    fi

    error "Failed to mount ADF. Install adf-util or amitools for better support"
    return 1
}

mount_amiga_hdf() {
    local file_path="$1"
    local mount_point="$2"

    log "Mounting Amiga HDF: $file_path -> $mount_point"

    mkdir -p "$mount_point"

    # Try rdbtool first to analyze the RDB structure
    local rdbtool_cmd=""
    if command -v rdbtool &> /dev/null; then
        rdbtool_cmd="rdbtool"
    elif command -v ~/.local/bin/rdbtool &> /dev/null; then
        rdbtool_cmd="~/.local/bin/rdbtool"
    elif python3 -m amitools.tools.rdbtool --help &> /dev/null 2>&1; then
        rdbtool_cmd="python3 -m amitools.tools.rdbtool"
    fi
    
    if [[ -n "$rdbtool_cmd" ]]; then
        log "Using $rdbtool_cmd for HDF analysis"
        echo -e "${BLUE}HDF Rigid Disk Block information:${NC}"
        local rdb_output=$(eval "$rdbtool_cmd" "$file_path" show 2>/dev/null)
        echo "$rdb_output"
        
        # Parse partition information to calculate offsets
        local partitions=$(echo "$rdb_output" | grep -A 20 "PartitionBlock" | grep -E "low_cyl:|high_cyl:|block_size:|drv_name:")
        if [[ -n "$partitions" ]]; then
            echo -e "\n${BLUE}Found partitions in HDF, attempting offset mounts:${NC}"
            
            # Extract first data partition info (skip swap partitions)
            local low_cyl=$(echo "$rdb_output" | grep -A 15 "drv_name:.*'sda0'" | grep "low_cyl:" | head -1 | awk '{print $2}')
            local block_size=$(echo "$rdb_output" | grep -A 15 "drv_name:.*'sda0'" | grep "block_size:" | head -1 | awk '{print $2}')
            local surfaces=$(echo "$rdb_output" | grep -A 15 "drv_name:.*'sda0'" | grep "surfaces:" | head -1 | awk '{print $2}')
            local blk_per_trk=$(echo "$rdb_output" | grep -A 15 "drv_name:.*'sda0'" | grep "blk_per_trk:" | head -1 | awk '{print $2}')
            
            if [[ -n "$low_cyl" ]] && [[ -n "$block_size" ]] && [[ -n "$surfaces" ]] && [[ -n "$blk_per_trk" ]]; then
                # Calculate offset: cylinder * heads * sectors * block_size
                local cyl_size=$((surfaces * blk_per_trk * block_size))
                local offset=$((low_cyl * cyl_size))
                
                echo "Partition sda0: low_cyl=$low_cyl, block_size=$block_size, calculated offset=$offset"
                
                # Try mounting with calculated offset
                log "Attempting to mount sda0 partition at offset $offset"
                if mount -o loop,offset=$offset,ro "$file_path" "$mount_point" 2>/dev/null; then
                    echo -e "${GREEN}Successfully mounted HDF partition sda0${NC}"
                    return 0
                fi
            fi
        fi
    fi

    # HDF files can contain multiple partitions
    # Try xdftool for partition extraction
    local xdftool_cmd=""
    
    # Check for xdftool in different ways
    if command -v xdftool &> /dev/null; then
        xdftool_cmd="xdftool"
    elif command -v ~/.local/bin/xdftool &> /dev/null; then
        xdftool_cmd="~/.local/bin/xdftool"
    elif python3 -m amitools.tools.xdftool --help &> /dev/null 2>&1; then
        xdftool_cmd="python3 -m amitools.tools.xdftool"
    fi
    
    if [[ -n "$xdftool_cmd" ]]; then
        log "Using $xdftool_cmd for HDF extraction"
        echo -e "${BLUE}Attempting partition extraction:${NC}"
        
        # Try to extract first partition, ignore boot block errors
        if eval "$xdftool_cmd" "$file_path" unpack 0 "$mount_point" 2>/dev/null; then
            echo -e "${GREEN}Successfully extracted HDF partition 0${NC}"
            return 0
        else
            warn "xdftool failed - HDF may have boot block issues or use unsupported filesystem (SFS)"
        fi
    fi

    # Try AFFS loop mount as fallback
    if grep -q affs /proc/filesystems 2>/dev/null; then
        log "Attempting AFFS loop mount for HDF"
        if mount -t affs -o loop,ro "$file_path" "$mount_point" 2>/dev/null; then
            echo -e "${GREEN}Successfully mounted HDF with AFFS${NC}"
            return 0
        fi
    else
        warn "AFFS filesystem not supported in kernel"
    fi

    # Try generic loop mount to see partitions
    log "Attempting to set up loop device to examine partitions"
    local loop_dev=$(losetup -f)
    if losetup "$loop_dev" "$file_path" 2>/dev/null; then
        echo -e "${BLUE}HDF partition table:${NC}"
        fdisk -l "$loop_dev" 2>/dev/null || true
        
        # Try to mount first partition if it exists
        if [[ -b "${loop_dev}p1" ]]; then
            log "Found partition ${loop_dev}p1, attempting mount"
            if mount -o loop,ro "${loop_dev}p1" "$mount_point" 2>/dev/null; then
                echo -e "${GREEN}Successfully mounted HDF partition 1${NC}"
                return 0
            fi
        fi
        
        # Clean up loop device
        losetup -d "$loop_dev" 2>/dev/null || true
    fi

    error "Failed to mount HDF."
    echo -e "${YELLOW}This HDF analysis:${NC}"
    echo "  - Filesystem type: $dos_type"
    echo "  - Partition name: $partition_name"
    echo -e "${YELLOW}Possible solutions:${NC}"
    if [[ "$dos_type" == "SFS0" ]] || [[ "$dos_type" == "SFS2" ]]; then
        echo "  - Use FS-UAE emulator: sudo apt install fs-uae"
        echo "  - Use UAE4ARM or WinUAE with this HDF"
    else
        echo "  - Try loading AFFS kernel module: sudo modprobe affs"
        echo "  - Use FS-UAE emulator as fallback"
        echo "  - Check if HDF is corrupted"
    fi
    echo "  - Convert to ADF format if possible"
    return 1
}

mount_amiga_dms() {
    local file_path="$1"
    local mount_point="$2"

    log "Processing Amiga DMS: $file_path -> $mount_point"

    mkdir -p "$mount_point"

    # DMS files need to be decompressed first
    local temp_adf="/tmp/$(basename "$file_path" .dms).adf"

    if command -v xdms &> /dev/null; then
        log "Decompressing DMS with xdms"
        if xdms u "$file_path" "$temp_adf" 2>/dev/null; then
            echo -e "${GREEN}Successfully decompressed DMS to ADF${NC}"
            # Now mount the ADF
            mount_amiga_adf "$temp_adf" "$mount_point"
            return $?
        fi
    fi

    error "Failed to decompress DMS. Install xdms: sudo apt install xdms"
    return 1
}

decompress_amiga_adz() {
    local file_path="$1"
    local mount_point="$2"

    log "Decompressing Amiga ADZ: $file_path -> $mount_point"

    mkdir -p "$mount_point"

    # ADZ is gzip-compressed ADF
    local temp_adf="/tmp/$(basename "$file_path" .adz).adf"

    if gunzip -c "$file_path" > "$temp_adf" 2>/dev/null; then
        echo -e "${GREEN}Successfully decompressed ADZ to ADF${NC}"
        # Now mount the ADF
        mount_amiga_adf "$temp_adf" "$mount_point"
        return $?
    fi

    error "Failed to decompress ADZ file"
    return 1
}

mount_apple_disk() {
    local file_path="$1"
    local mount_point="$2"
    local filename=$(basename "$file_path")

    log "Mounting Apple II disk: $file_path -> $mount_point"
    mkdir -p "$mount_point"

    case "${filename,,}" in
        *.2mg|*.2img)
            # 2MG format has header, try AppleCommander
            if command -v ac &> /dev/null; then
                log "Using AppleCommander for 2MG"
                if ac -l "$file_path" > "$mount_point/catalog.txt" 2>/dev/null; then
                    echo -e "${GREEN}Successfully listed 2MG contents${NC}"
                    echo -e "${YELLOW}Files extracted to: $mount_point/catalog.txt${NC}"
                    return 0
                fi
            fi
            ;;
        *.dsk|*.do|*.po)
            # Try mounting as FAT12 (some Apple disks use this)
            if mount -t msdos -o loop,ro "$file_path" "$mount_point" 2>/dev/null; then
                echo -e "${GREEN}Successfully mounted Apple disk as FAT12${NC}"
                return 0
            fi

            # Try AppleCommander for file extraction
            if command -v ac &> /dev/null; then
                log "Using AppleCommander for DSK/DO/PO"
                if ac -l "$file_path" > "$mount_point/catalog.txt" 2>/dev/null; then
                    echo -e "${GREEN}Successfully listed disk contents${NC}"
                    echo -e "${YELLOW}Catalog saved to: $mount_point/catalog.txt${NC}"
                    return 0
                fi
            fi
            ;;
    esac

    error "Failed to mount Apple II disk. Install AppleCommander or CiderPress"
    return 1
}

mount_atari_disk() {
    local file_path="$1"
    local mount_point="$2"
    local filename=$(basename "$file_path")

    log "Mounting Atari disk: $file_path -> $mount_point"
    mkdir -p "$mount_point"

    case "${filename,,}" in
        *.st)
            # ST files are often FAT12
            if mount -t msdos -o loop,ro "$file_path" "$mount_point" 2>/dev/null; then
                echo -e "${GREEN}Successfully mounted Atari ST disk as FAT12${NC}"
                return 0
            fi
            ;;
        *.msa)
            # MSA files need decompression first
            local temp_st="/tmp/$(basename "$file_path" .msa).st"
            if command -v msa &> /dev/null; then
                log "Decompressing MSA with msa tool"
                if msa -d "$file_path" "$temp_st" 2>/dev/null; then
                    mount_atari_disk "$temp_st" "$mount_point"
                    return $?
                fi
            fi
            ;;
        *.atr)
            # Atari 8-bit format
            if mount -o loop,ro "$file_path" "$mount_point" 2>/dev/null; then
                echo -e "${GREEN}Successfully mounted Atari 8-bit ATR${NC}"
                return 0
            fi
            ;;
    esac

    # Try generic loop mount
    if mount -o loop,ro "$file_path" "$mount_point" 2>/dev/null; then
        echo -e "${GREEN}Successfully mounted Atari disk${NC}"
        return 0
    fi

    error "Failed to mount Atari disk. Install Hatari tools or STeem"
    return 1
}

mount_trs80_disk() {
    local file_path="$1"
    local mount_point="$2"
    local filename=$(basename "$file_path")

    log "Processing TRS-80 disk: $file_path -> $mount_point"
    mkdir -p "$mount_point"

    # TRS-80 disks need special tools for file extraction
    if command -v trsread &> /dev/null; then
        log "Using trsread for TRS-80 disk"
        if trsread -e "$file_path" "$mount_point" 2>/dev/null; then
            echo -e "${GREEN}Successfully extracted TRS-80 files${NC}"
            return 0
        fi
    fi

    # Try listing directory only
    if command -v trsread &> /dev/null; then
        if trsread -v "$file_path" > "$mount_point/directory.txt" 2>/dev/null; then
            echo -e "${GREEN}Successfully listed TRS-80 directory${NC}"
            echo -e "${YELLOW}Directory saved to: $mount_point/directory.txt${NC}"
            return 0
        fi
    fi

    error "Failed to process TRS-80 disk. Install TRSTools or xtrs"
    return 1
}

mount_commodore_disk() {
    local file_path="$1"
    local mount_point="$2"
    local filename=$(basename "$file_path")

    log "Processing Commodore disk: $file_path -> $mount_point"
    mkdir -p "$mount_point"

    # Use c1541 from VICE emulator
    if command -v c1541 &> /dev/null; then
        case "${filename,,}" in
            *.d64|*.d71|*.d81)
                log "Using c1541 for Commodore disk"
                # List directory
                if c1541 "$file_path" -list > "$mount_point/directory.txt" 2>/dev/null; then
                    echo -e "${GREEN}Successfully listed Commodore directory${NC}"

                    # Extract all files
                    if c1541 "$file_path" -extract 2>/dev/null; then
                        # Move extracted files to mount point
                        mv ./*.prg "$mount_point/" 2>/dev/null || true
                        mv ./*.seq "$mount_point/" 2>/dev/null || true
                        mv ./*.usr "$mount_point/" 2>/dev/null || true
                        echo -e "${GREEN}Successfully extracted Commodore files${NC}"
                    fi
                    return 0
                fi
                ;;
            *.t64)
                # T64 tape format
                if c1541 "$file_path" -list > "$mount_point/directory.txt" 2>/dev/null; then
                    echo -e "${GREEN}Successfully listed T64 contents${NC}"
                    return 0
                fi
                ;;
        esac
    fi

    error "Failed to process Commodore disk. Install: sudo apt install vice"
    return 1
}

list_loop_devices() {
    echo -e "${BLUE}Current loop devices:${NC}"
    losetup -l
    echo ""
    echo -e "${BLUE}Available loop devices:${NC}"
    losetup -f
}

unmount_path() {
    local mount_point="$1"

    if mountpoint -q "$mount_point"; then
        log "Unmounting $mount_point"
        umount "$mount_point"
        echo -e "${GREEN}Successfully unmounted: $mount_point${NC}"

        # Clean up loop device if it was used
        local loop_dev=$(losetup -j "$mount_point" 2>/dev/null | cut -d: -f1)
        if [[ -n "$loop_dev" ]]; then
            losetup -d "$loop_dev"
            log "Cleaned up loop device: $loop_dev"
        fi
    else
        warn "$mount_point is not mounted"
    fi
}

install_retro_tools() {
    echo -e "${BLUE}Installing retro computer filesystem tools...${NC}"

    echo "=== AVAILABLE IN STANDARD REPOS ==="
    echo "  - adf-util: sudo apt install adf-util"
    echo "  - xdms: sudo apt install xdms"
    echo "  - VICE (c1541): sudo apt install vice"
    echo "  - Hatari: sudo apt install hatari"
    echo "  - nulib2: sudo apt install nulib2"
    echo ""

    echo "=== MANUAL INSTALL REQUIRED ==="
    echo ""
    echo "AMIGA TOOLS:"
    echo "  - amitools (xdftool): pip3 install amitools"
    echo "  - UAE4ARM/FS-UAE: Download from respective websites"
    echo ""

    echo "APPLE II TOOLS:"
    echo "  - AppleCommander: Download JAR from https://applecommander.github.io/"
    echo "  - CiderPress: Download from https://a2ciderpress.com/"
    echo "  - linapple: Build from source or AppImage"
    echo ""

    echo "ATARI TOOLS:"
    echo "  - STeem: Download from http://steem.atari.st/"
    echo "  - Hatari MSA tools: Included with hatari package"
    echo ""

    echo "TRS-80 TOOLS:"
    echo "  - TRSTools: Download from https://www.trs-80emulators.com/trstools/"
    echo "  - xtrs: Build from source (https://github.com/TimothyPMann/xtrs)"
    echo ""

    echo "COMMODORE TOOLS:"
    echo "  - opencbm: sudo apt install opencbm (if available)"
    echo "  - Additional VICE tools: Included with vice package"
    echo ""

    echo "=== GENERAL DISK TOOLS ==="
    echo "  - HxC Floppy Emulator: https://hxc2001.com/"
    echo "  - Greaseweazle: https://github.com/keirf/greaseweazle"
    echo "  - SamDisk: https://simonowen.com/samdisk/"
    echo ""

    read -p "Install available packages from repos now? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing available packages..."
        apt update

        # Install only what's actually available in most repos
        local packages_to_install=()
        
        # Check each package individually
        if apt-cache show adf-util &>/dev/null; then
            packages_to_install+=(adf-util)
        fi
        
        if apt-cache show xdms &>/dev/null; then
            packages_to_install+=(xdms)
        fi
        
        if apt-cache show vice &>/dev/null; then
            packages_to_install+=(vice)
        fi
        
        if apt-cache show hatari &>/dev/null; then
            packages_to_install+=(hatari)
        fi
        
        if apt-cache show nulib2 &>/dev/null; then
            packages_to_install+=(nulib2)
        fi
        
        if apt-cache show opencbm &>/dev/null; then
            packages_to_install+=(opencbm)
        fi

        # Always try to install hex dump tools
        if apt-cache show xxd &>/dev/null; then
            packages_to_install+=(xxd)
        fi

        if [[ ${#packages_to_install[@]} -gt 0 ]]; then
            echo "Installing: ${packages_to_install[*]}"
            apt install -y "${packages_to_install[@]}" || warn "Some packages failed to install"
            echo -e "${GREEN}Available packages installed!${NC}"
        else
            warn "No retro computing packages found in repositories"
        fi

        echo ""
        echo -e "${YELLOW}Additional manual installations:${NC}"
        echo "  Python tools: pip3 install amitools"
        echo "  Check the URLs above for other tools"
    fi
}

main() {
    local file_path=""
    local mount_point="$DEFAULT_MOUNT"
    local fs_type=""
    local ramdisk_size=""
    local check_only=false
    local unmount_mode=false
    local list_mode=false
    local install_retro=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mount-point)
                mount_point="$2"
                shift 2
                ;;
            -r|--ramdisk)
                ramdisk_size="$2"
                shift 2
                ;;
            -t|--type)
                fs_type="$2"
                shift 2
                ;;
            -u|--umount)
                unmount_mode=true
                shift
                ;;
            -l|--list)
                list_mode=true
                shift
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -i|--install-retro)
                install_retro=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -z "$file_path" ]]; then
                    file_path="$1"
                else
                    mount_point="$1"
                fi
                shift
                ;;
        esac
    done

    # Handle special modes
    if [[ $install_retro == true ]]; then
        check_root
        install_retro_tools
        exit 0
    fi

    check_dependencies
    check_root

    if [[ $list_mode == true ]]; then
        list_loop_devices
        exit 0
    fi

    if [[ $unmount_mode == true ]]; then
        if [[ -z "$file_path" ]]; then
            unmount_path "$mount_point"
        else
            unmount_path "$file_path"
        fi
        exit 0
    fi

    if [[ -n "$ramdisk_size" ]]; then
        create_ramdisk "$ramdisk_size" "$mount_point"
        exit 0
    fi

    # Validate input
    if [[ -z "$file_path" ]]; then
        error "No filesystem image specified"
        usage
        exit 1
    fi

    # Check filesystem
    if ! detect_filesystem "$file_path"; then
        if [[ $check_only == false ]]; then
            warn "Attempting generic mount anyway..."
        fi
    fi

    if [[ $check_only == true ]]; then
        exit 0
    fi

    # Mount based on detected type
    local file_info=$(file "$file_path")
    local filename=$(basename "$file_path")

    echo -e "\n${BLUE}Mounting filesystem...${NC}"

    # Check for Amiga formats first (by extension and content)
    case "${filename,,}" in
        *.adf)
            mount_amiga_adf "$file_path" "$mount_point"
            ;;
        *.hdf)
            mount_amiga_hdf "$file_path" "$mount_point"
            ;;
        *.dms)
            mount_amiga_dms "$file_path" "$mount_point"
            ;;
        *.adz)
            decompress_amiga_adz "$file_path" "$mount_point"
            ;;
        *.dsk|*.do|*.po|*.2mg|*.nib|*.woz|*.hdv|*.d13)
            mount_apple_disk "$file_path" "$mount_point"
            ;;
        *.st|*.msa|*.stx|*.dim|*.ipf|*.atr)
            mount_atari_disk "$file_path" "$mount_point"
            ;;
        *.jv1|*.jv3|*.dmk)
            mount_trs80_disk "$file_path" "$mount_point"
            ;;
        *.d64|*.d71|*.d81|*.t64|*.prg|*.p00|*.g64)
            mount_commodore_disk "$file_path" "$mount_point"
            ;;
        *)
            # Check by content
            if [[ $file_info == *"Squashfs"* ]]; then
                mount_squashfs "$file_path" "$mount_point"
            elif [[ $file_info == *"ISO 9660"* ]]; then
                mount_iso "$file_path" "$mount_point"
            elif check_amiga_filesystem "$file_path" >/dev/null 2>&1; then
                # Detected as Amiga format by content analysis
                local size_bytes=$(stat -c%s "$file_path" 2>/dev/null || echo 0)
                if [[ $size_bytes -eq 901120 ]] || [[ $size_bytes -eq 1802240 ]]; then
                    mount_amiga_adf "$file_path" "$mount_point"
                elif [[ $size_bytes -gt 1802240 ]]; then
                    mount_amiga_hdf "$file_path" "$mount_point"
                else
                    mount_generic "$file_path" "$mount_point" "$fs_type"
                fi
            elif check_apple_filesystem "$file_path" >/dev/null 2>&1; then
                mount_apple_disk "$file_path" "$mount_point"
            elif check_atari_filesystem "$file_path" >/dev/null 2>&1; then
                mount_atari_disk "$file_path" "$mount_point"
            elif check_trs80_filesystem "$file_path" >/dev/null 2>&1; then
                mount_trs80_disk "$file_path" "$mount_point"
            elif check_commodore_filesystem "$file_path" >/dev/null 2>&1; then
                mount_commodore_disk "$file_path" "$mount_point"
            else
                mount_generic "$file_path" "$mount_point" "$fs_type"
            fi
            ;;
    esac

    # Show mount info
    echo -e "\n${GREEN}Mount successful!${NC}"
    echo "Filesystem: $file_path"
    echo "Mount point: $mount_point"
    echo "Type: $(findmnt -n -o FSTYPE "$mount_point" 2>/dev/null || echo "extracted/unknown")"

    # Show contents preview
    echo -e "\n${BLUE}Contents preview:${NC}"
    ls -la "$mount_point" | head -10

    echo -e "\n${YELLOW}To unmount:${NC} $0 -u $mount_point"
}

# Set default verbose to false
VERBOSE=false

main "$@"