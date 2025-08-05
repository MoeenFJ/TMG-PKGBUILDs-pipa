#!/bin/bash

# Paths to files
IMAGE_FILE="/boot/Image.gz"
DTB_FILE="/boot/dtbs/qcom/sm8250-xiaomi-pipa.dtb"
OUTPUT_FILE="/boot/zImage.gz"

# Check if IMAGE_FILE exists and is not empty
if [[ ! -s "$IMAGE_FILE" ]]; then
    echo "Error: $IMAGE_FILE does not exist or is empty."
    exit 1
fi

# Check if DTB_FILE exists and is not empty
if [[ ! -s "$DTB_FILE" ]]; then
    echo "Error: $DTB_FILE does not exist or is empty."
    exit 1
fi

# Concatenate only if both checks pass
cat "$IMAGE_FILE" "$DTB_FILE" > "$OUTPUT_FILE"
echo "Successfully generated $OUTPUT_FILE"

CMDLINE_FILE="/boot/cmdline.txt"

# Check if cmdline file exists and is not empty
if [[ ! -s "$CMDLINE_FILE" ]]; then
    echo "Error: cmdline file $CMDLINE_FILE does not exist or is empty."
    exit 1
fi

# Read cmdline from file (strip trailing newlines)
CMDLINE=$(tr -d '\n' < "$CMDLINE_FILE")

mkbootimg_pipa \
	 --kernel /boot/zImage.gz \
 	 --ramdisk /boot/initramfs.img \
	 --cmdline "$CMDLINE" \
	 --kernel_offset 0x00008000 \
	 --ramdisk_offset 0x01000000 \
	 --second_offset 0x00000000 \
	 --tags_offset 0x00000100 \
	 --header_version 0 \
	 --pagesize 4096 \
	 --hashtype sha1 \
	 -o /boot/boot.img

if [[ $? -ne 0 ]]; then
    echo "Error: mkbootimg failed to create boot.img"
    exit 1
fi

if [[ ! -s /boot/boot.img ]]; then
    echo "Error: boot.img was not created or is empty."
    exit 1
fi

echo "Successful generated /boot/boot.img"

# Fetch the active slot safely

AUTOFLASH_FILE="/boot/.autoflash"

# Get active slot via qbootctl
ACTIVE_SLOT=$(sudo qbootctl -a 2>/dev/null | grep -oP 'Active slot:\s*\K\S+')

# Check if .autoflash exists
if [[ -f "$AUTOFLASH_FILE" ]]; then
    CONTENT=$(<"$AUTOFLASH_FILE")
    if [[ "$CONTENT" == "a" || "$CONTENT" == "b" ]]; then
        ACTIVE_SLOT="_$CONTENT"
        echo "Overriding active slot using $AUTOFLASH_FILE: $ACTIVE_SLOT"
    fi
else
    if [[ -t 0 ]]; then
        # when script is run manually
        read -rp "Do you want to flash boot.img to active slot '$ACTIVE_SLOT'? [y/N]: " RESP
        if [[ ! "$RESP" =~ ^[Yy]$ ]]; then
            echo "Aborted by user."
            exit 1
        fi
        echo "Enable automatic flashing with:"
        echo "  sudo touch /boot/.autoflash"
    else
        # when run as pacman hook
        echo "Automatic flashing skipped."
        echo "To flash the boot image to the active slot ('$ACTIVE_SLOT'), run:"
        echo "  sudo /usr/bin/flashkernel.sh"
        echo
        echo "To enable automatic flashing in the future, create this file:"
        echo "  sudo touch /boot/.autoflash"
        echo
        echo "No action was taken. You must manually flash the boot image if needed."
        exit 0
    fi
fi


# Check if fetching the slot succeeded and if the value is valid (not empty)
if [[ $? -ne 0 || -z "$ACTIVE_SLOT" ]]; then
    echo "Error: Failed to fetch active slot or active slot is empty."
    exit 1
fi

echo "Active slot: $ACTIVE_SLOT"

DEVICE=$(sudo blkid | grep "\"boot${ACTIVE_SLOT}\"" | awk '{print $1}' | tr -d ':')

# Confirm the device path
if [[ -z "$DEVICE" ]]; then
    echo "Error: No device found matching the criteria."
    exit 1
fi

# Write the disk image
echo "Writing to Active slot"
sudo dd if="/boot/boot.img" of="$DEVICE" bs=1M status=progress

if [[ $? -ne 0 ]]; then
    echo "Error: Flashing Boot image "
    exit 1
fi

sync

echo "Disk image successfully written to $DEVICE, Ramdisk/Kernel Updated."

rm /boot/zImage.gz
