#!/system/bin/sh
# Archimedes / MT6761 64G only: resize system to exactly 2.5 GiB.
# Run only from a root TWRP adb shell. This script never flashes images.

set -eu

DISK=/dev/block/mmcblk0
TARGET_SECTORS=5242880       # 2.5 GiB / 512 bytes
SYSTEM_START=1802240
VBMETA_START=7045120
VBMETA_END=7074623
CACHE_START=7074624
CACHE_END=7959359
USERDATA_START=7959360
OTP_START=122021855
OTP_END=122109918
FLASHINFO_START=122109919
FLASHINFO_END=122142686
VBMETA_SECTORS=14752
CACHE_SECTORS=442368

fail() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }
part_start() { "$SGDISK" --info="$1" "$DISK" 2>/dev/null | awk '/First sector:/ {gsub(",", "", $3); print $3; exit}'; }
part_end() { "$SGDISK" --info="$1" "$DISK" 2>/dev/null | awk '/Last sector:/ {gsub(",", "", $3); print $3; exit}'; }
part_size() { "$SGDISK" --info="$1" "$DISK" 2>/dev/null | awk '/Partition size:/ {gsub(",", "", $3); print $3; exit}'; }
part_guid() { "$SGDISK" --info="$1" "$DISK" 2>/dev/null | awk -F': ' '/Partition unique GUID:/ {print $2; exit}'; }

[ "$#" -eq 0 ] || fail "do not pass parameters; type y only when prompted"
[ "$(id -u)" = 0 ] || fail "open TWRP adb shell as root"
[ -b "$DISK" ] || fail "$DISK is not available"
need awk
need grep
need blockdev
SGDISK=$(command -v sgdisk || true)
[ -n "$SGDISK" ] || [ -x /sbin/sgdisk ] || fail "sgdisk is missing from TWRP"
[ -n "$SGDISK" ] || SGDISK=/sbin/sgdisk

MODE=$(getprop ro.bootmode 2>/dev/null || true)
[ "$MODE" = recovery ] || fail "boot mode is '$MODE'; run this only in TWRP/recovery"
CMDLINE=$(cat /proc/cmdline 2>/dev/null || true)
echo "$CMDLINE" | grep -Eq 'androidboot.hardware=mt6761|platform=mt6761' || fail "not an MT6761 boot"

TOTAL_BYTES=$(blockdev --getsize64 "$DISK" 2>/dev/null || echo 0)
[ "$TOTAL_BYTES" -ge 62000000000 ] && [ "$TOTAL_BYTES" -le 63000000000 ] || \
    fail "not the Archimedes 64G eMMC (bytes=$TOTAL_BYTES)"

P31_START=$(part_start 31); P31_SIZE=$(part_size 31)
P32_START=$(part_start 32); P32_END=$(part_end 32); P32_SIZE=$(part_size 32)
P33_START=$(part_start 33); P33_END=$(part_end 33); P33_SIZE=$(part_size 33)
P34_START=$(part_start 34); P34_END=$(part_end 34)
P35_START=$(part_start 35); P35_END=$(part_end 35)
P36_START=$(part_start 36); P36_END=$(part_end 36)
for value in "$P31_START" "$P31_SIZE" "$P32_START" "$P32_END" "$P32_SIZE" \
    "$P33_START" "$P33_END" "$P33_SIZE" "$P34_START" "$P34_END" \
    "$P35_START" "$P35_END" "$P36_START" "$P36_END"; do
    echo "$value" | grep -Eq '^[0-9]+$' || fail "cannot read current GPT"
done

# The script is safe to rerun after a successful resize.
if [ "$P31_START" = "$SYSTEM_START" ] && [ "$P31_SIZE" = "$TARGET_SECTORS" ] \
   && [ "$P32_START" = "$VBMETA_START" ] && [ "$P32_END" = "$VBMETA_END" ] \
   && [ "$P33_START" = "$CACHE_START" ] && [ "$P33_END" = "$CACHE_END" ]; then
    echo "system is already exactly 2.5 GiB; no changes made"
    exit 0
fi

[ "$P31_START" = "$SYSTEM_START" ] || fail "unexpected system start sector"
[ "$P31_SIZE" -lt "$TARGET_SECTORS" ] || fail "system is already at or above 2.5 GiB"
[ "$P32_SIZE" = "$VBMETA_SECTORS" ] || fail "unexpected vbmeta size"
[ "$P33_SIZE" = "$CACHE_SECTORS" ] || fail "unexpected cache size"
[ "$P34_END" = "$((P35_START - 1))" ] || fail "userdata/OTP are not contiguous"
[ "$P35_START" = "$OTP_START" ] && [ "$P35_END" = "$OTP_END" ] || fail "unexpected OTP boundary"
[ "$P36_START" = "$FLASHINFO_START" ] && [ "$P36_END" = "$FLASHINFO_END" ] || fail "unexpected flashinfo boundary"

for mountpoint in /system /vendor /product /data /cache /sdcard; do
    grep -q " $mountpoint " /proc/mounts 2>/dev/null && fail "$mountpoint is mounted; unmount it first"
done

cat <<'WARNING'

!!! DESTRUCTIVE OPERATION — ARCHIMEDES 64G ONLY !!!
This will recreate the GPT entries for system/vbmeta/cache/userdata.
The existing userdata filesystem and its contents WILL BE LOST.
The operation can corrupt the partition table, erase data, or permanently
brick the device if it is interrupted or used on another model/capacity.
Keep the scatter file and a full recovery path ready. The script does not
flash images automatically. Only a lowercase 'y' continues.

WARNING
printf "Type y to accept all risks: "
read ANSWER
[ "$ANSWER" = y ] || fail "confirmation was not exactly 'y'"

BACKUP=/tmp/archimedes-gpt-before-2.5g.bin
G31=$(part_guid 31); G32=$(part_guid 32); G33=$(part_guid 33); G34=$(part_guid 34)
for guid in "$G31" "$G32" "$G33" "$G34"; do
    echo "$guid" | grep -Eq '^[0-9A-Fa-f-]{36}$' || fail "cannot read partition GUIDs"
done

"$SGDISK" --backup="$BACKUP" "$DISK" || fail "could not back up GPT to $BACKUP"
sync
"$SGDISK" --delete=34 --delete=33 --delete=32 --delete=31 "$DISK" || \
    fail "GPT delete failed; do not reboot; backup is $BACKUP"
"$SGDISK" --new=31:${SYSTEM_START}:$((VBMETA_START - 1)) --typecode=31:0700 \
    --change-name=31:system --partition-guid=31:$G31 "$DISK" || fail "system entry failed"
"$SGDISK" --new=32:${VBMETA_START}:${VBMETA_END} --typecode=32:0700 \
    --change-name=32:vbmeta --partition-guid=32:$G32 "$DISK" || fail "vbmeta entry failed"
"$SGDISK" --new=33:${CACHE_START}:${CACHE_END} --typecode=33:0700 \
    --change-name=33:cache --partition-guid=33:$G33 "$DISK" || fail "cache entry failed"
"$SGDISK" --new=34:${USERDATA_START}:$((OTP_START - 1)) --typecode=34:0700 \
    --change-name=34:userdata --partition-guid=34:$G34 "$DISK" || fail "userdata entry failed"
"$SGDISK" --verify "$DISK" || fail "GPT verification failed; do not reboot; backup is $BACKUP"
sync

echo
echo "DONE: system is now exactly 2.5 GiB."
echo "Reboot back into TWRP before formatting userdata and flashing images."
echo "Temporary GPT backup: $BACKUP"
