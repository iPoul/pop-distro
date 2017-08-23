DISTRO_VERSION?=17.10

DISTRO_EPOCH?=$(shell date +%s)

DISTRO_DATE?=$(shell date +%Y%M%d)

DISTRO_NAME=Pop_OS

DISTRO_CODE=pop-os

DISTRO_REPOS=\
	main \
	universe \
	restricted \
	multiverse \
	ppa:system76/pop

DISTRO_PKGS=\
	pop-desktop

LIVE_PKGS=\
	casper \
	jfsutils \
	linux-generic \
	lupin-casper \
	mokutil \
	mtools \
	reiserfsprogs \
	ubiquity-frontend-gtk \
	ubiquity-slideshow-pop \
	xfsprogs \
	ubuntu-standard \
	ubuntu-minimal \
	language-pack-gnome-de \
	language-pack-gnome-en \
	language-pack-gnome-es \
	language-pack-gnome-fr \
	language-pack-gnome-it \
	language-pack-gnome-pt \
	language-pack-gnome-ru \
	language-pack-gnome-zh-hans

RM_PKGS=\
	imagemagick-6.q16

MAIN_POOL=\
	b43-fwcutter \
	dkms \
	grub-efi \
	grub-efi-amd64 \
	grub-efi-amd64-bin \
	grub-efi-amd64-signed \
	libuniconf4.6 \
	libwvstreams4.6-base \
	libwvstreams4.6-extras \
	lupin-support \
	mouseemu \
	oem-config \
	oem-config-gtk \
	oem-config-slideshow-ubuntu \
	setserial \
	shim \
	shim-signed \
	user-setup \
	wvdial

RESTRICTED_POOL=\
	bcmwl-kernel-source \
	intel-microcode \
	iucode-tool

ifeq ($(DISTRO_VERSION),17.04)
	UBUNTU_CODE=zesty
	UBUNTU_NAME=Zesty Zapus
	UBUNTU_ISO=http://cdimage.ubuntu.com/ubuntu-gnome/releases/17.04/release/ubuntu-gnome-17.04-desktop-amd64.iso
else ifeq ($(DISTRO_VERSION),17.10)
	UBUNTU_CODE=artful
	UBUNTU_NAME=Artful Aardvark
	UBUNTU_ISO=http://cdimage.ubuntu.com/ubuntu/daily-live/current/artful-desktop-amd64.iso
endif

BUILD=build/$(DISTRO_VERSION)

SED=\
	s|DISTRO_NAME|$(DISTRO_NAME)|g; \
	s|DISTRO_CODE|$(DISTRO_CODE)|g; \
	s|DISTRO_VERSION|$(DISTRO_VERSION)|g; \
	s|DISTRO_DATE|$(DISTRO_DATE)|g; \
	s|DISTRO_EPOCH|$(DISTRO_EPOCH)|g; \
	s|DISTRO_REPOS|$(DISTRO_REPOS)|g; \
	s|DISTRO_PKGS|$(DISTRO_PKGS)|g; \
	s|UBUNTU_CODE|$(UBUNTU_CODE)|g; \
	s|UBUNTU_NAME|$(UBUNTU_NAME)|g

XORRISO=$(shell command -v xorriso 2> /dev/null)
ZSYNC=$(shell command -v zsync 2> /dev/null)
SQUASHFS=$(shell command -v mksquashfs 2> /dev/null)

# Ensure that `zsync` is installed already
ifeq (,$(ZSYNC))
$(error zsync not found! Run deps.sh first.)
endif
# Ensure that `xorriso` is installed already
ifeq (,$(XORRISO))
$(error xorriso not found! Run deps.sh first.)
endif
# Ensure that `squashfs` is installed already
ifeq (,$(SQUASHFS))
$(error squashfs-tools not found! Run deps.sh first.)
endif

.PHONY: all clean distclean iso qemu qemu_uefi qemu_ubuntu qemu_ubuntu_uefi zsync

iso: $(BUILD)/$(DISTRO_CODE).iso

all: $(BUILD)/$(DISTRO_CODE).iso $(BUILD)/$(DISTRO_CODE).iso.zsync $(BUILD)/SHA256SUMS $(BUILD)/SHA256SUMS.gpg

clean:
	# Unmount chroot if mounted
	scripts/unmount.sh "$(BUILD)/chroot"

	# Remove chroot
	sudo rm -rf "$(BUILD)/chroot"

	# Remove ISO extract
	sudo rm -rf "$(BUILD)/iso"

	# Remove tag files, partial files, and build artifacts
	rm -f $(BUILD)/*.tag $(BUILD)/*.partial $(BUILD)/$(DISTRO_CODE).tar $(BUILD)/$(DISTRO_CODE).iso $(BUILD)/$(DISTRO_CODE).iso.zsync $(BUILD)/SHA256SUMS $(BUILD)/SHA256SUMS.gpg

	# Remove QEMU files
	rm -f $(BUILD)/*.img $(BUILD)/OVMF_VARS.fd

distclean:
	# Remove debootstrap
	sudo rm -rf "$(BUILD)/debootstrap"

	# Execute normal clean
	make clean

$(BUILD)/%.img:
	mkdir -p $(BUILD)
	qemu-img create -f qcow2 "$@.partial" 16G

	mv "$@.partial" "$@"

qemu: $(BUILD)/$(DISTRO_CODE).iso $(BUILD)/qemu.img
	qemu-system-x86_64 -name "$(DISTRO_NAME) $(DISTRO_VERSION) BIOS" \
		-enable-kvm -m 2048 -vga qxl \
		-hda $(BUILD)/qemu.img \
		-boot d -cdrom "$<"

qemu_uefi: $(BUILD)/$(DISTRO_CODE).iso $(BUILD)/qemu_uefi.img
	cp /usr/share/OVMF/OVMF_VARS.fd $(BUILD)/OVMF_VARS.fd
	qemu-system-x86_64 -name "$(DISTRO_NAME) $(DISTRO_VERSION) UEFI" \
		-enable-kvm -m 2048 -vga qxl \
		-drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=$(BUILD)/OVMF_VARS.fd \
		-hda $(BUILD)/qemu_uefi.img \
		-boot d -cdrom "$<"

qemu_uefi_usb: $(BUILD)/$(DISTRO_CODE).iso $(BUILD)/qemu_uefi.img
	cp /usr/share/OVMF/OVMF_VARS.fd $(BUILD)/OVMF_VARS.fd
	qemu-system-x86_64 -name "$(DISTRO_NAME) $(DISTRO_VERSION) UEFI" \
		-enable-kvm -m 2048 -vga qxl \
		-drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=$(BUILD)/OVMF_VARS.fd \
		-hda $(BUILD)/qemu_uefi.img \
		-boot d -drive if=none,id=iso,file="$<" \
		-device nec-usb-xhci,id=xhci \
		-device usb-storage,bus=xhci.0,drive=iso

qemu_ubuntu: $(BUILD)/ubuntu.iso $(BUILD)/qemu.img
	qemu-system-x86_64 -name "Ubuntu $(DISTRO_VERSION) BIOS" \
		-enable-kvm -m 2048 -vga qxl \
		-hda $(BUILD)/qemu.img \
		-boot d -cdrom "$<"

qemu_ubuntu_uefi: $(BUILD)/ubuntu.iso $(BUILD)/qemu_uefi.img
	cp /usr/share/OVMF/OVMF_VARS.fd $(BUILD)/OVMF_VARS.fd
	qemu-system-x86_64 -name "Ubuntu $(DISTRO_VERSION) UEFI" \
		-enable-kvm -m 2048 -vga qxl \
		-drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=$(BUILD)/OVMF_VARS.fd \
		-hda $(BUILD)/qemu_uefi.img \
		-boot d -cdrom "$<"

$(BUILD)/ubuntu.iso:
	mkdir -p $(BUILD)
	wget -O "$@.partial" "$(UBUNTU_ISO)"

	mv "$@.partial" "$@"

zsync: $(BUILD)/ubuntu.iso
	zsync "$(UBUNTU_ISO).zsync" -o "$<"

$(BUILD)/debootstrap:
	# Remove old debootstrap
	sudo rm -rf "$@" "$@.partial"

	# Install using debootstrap
	sudo debootstrap --arch=amd64 --include=software-properties-common "$(UBUNTU_CODE)" "$@.partial"

	mv "$@.partial" "$@"

$(BUILD)/iso_extract.tag:
	# Remove old ISO
	sudo rm -rf "$(BUILD)/iso"

	# Create ISO directory
	mkdir -p "$(BUILD)/iso"

	touch "$@"

$(BUILD)/chroot_extract.tag: $(BUILD)/debootstrap
	# Unmount chroot if mounted
	scripts/unmount.sh "$(BUILD)/chroot"

	# Remove old chroot
	sudo rm -rf "$(BUILD)/chroot"

	# Copy debootstrap to chroot
	sudo cp -a "$(BUILD)/debootstrap" "$(BUILD)/chroot"

	touch "$@"

$(BUILD)/chroot_modify.tag: $(BUILD)/chroot_extract.tag $(BUILD)/iso_extract.tag
	# Unmount chroot if mounted
	"scripts/unmount.sh" "$(BUILD)/chroot"

	# Make temp directory for modifications
	sudo rm -rf "$(BUILD)/chroot/iso"
	sudo mkdir -p "$(BUILD)/chroot/iso"

	# Copy chroot script
	sudo cp "scripts/chroot.sh" "$(BUILD)/chroot/iso/chroot.sh"

	# Mount chroot
	"scripts/mount.sh" "$(BUILD)/chroot"

	# Run chroot script
	sudo chroot "$(BUILD)/chroot" /bin/bash -e -c \
		"DISTRO_NAME=\"$(DISTRO_NAME)\" \
		DISTRO_CODE=\"$(DISTRO_CODE)\" \
		DISTRO_VERSION=\"$(DISTRO_VERSION)\" \
		DISTRO_REPOS=\"$(DISTRO_REPOS)\" \
		DISTRO_PKGS=\"$(DISTRO_PKGS)\" \
		LIVE_PKGS=\"$(LIVE_PKGS)\" \
		RM_PKGS=\"$(RM_PKGS)\" \
		MAIN_POOL=\"$(MAIN_POOL)\" \
		RESTRICTED_POOL=\"$(RESTRICTED_POOL)\" \
		/iso/chroot.sh"

	# Unmount chroot
	"scripts/unmount.sh" "$(BUILD)/chroot"

	# Create missing network-manager file
	sudo touch "$(BUILD)/chroot/etc/NetworkManager/conf.d/10-globally-managed-devices.conf"

	# Patch ubiquity by removing plugins and updating order
	sudo sed -i "s/^AFTER = .*\$$/AFTER = 'language'/" "$(BUILD)/chroot/usr/lib/ubiquity/plugins/ubi-console-setup.py"
	sudo sed -i "s/^AFTER = .*\$$/AFTER = 'console_setup'/" "$(BUILD)/chroot/usr/lib/ubiquity/plugins/ubi-partman.py"
	sudo sed -i "s/^AFTER = .*\$$/AFTER = 'partman'/" "$(BUILD)/chroot/usr/lib/ubiquity/plugins/ubi-timezone.py"
	sudo rm -f "$(BUILD)/chroot/usr/lib/ubiquity/plugins/ubi-prepare.py"
	sudo rm -f "$(BUILD)/chroot/usr/lib/ubiquity/plugins/ubi-network.py"
	sudo rm -f "$(BUILD)/chroot/usr/lib/ubiquity/plugins/ubi-tasks.py"
	sudo rm -f "$(BUILD)/chroot/usr/lib/ubiquity/plugins/ubi-usersetup.py"
	sudo rm -f "$(BUILD)/chroot/usr/lib/ubiquity/plugins/ubi-wireless.py"

	# Remove gnome-classic
	sudo rm -f "$(BUILD)/chroot/usr/share/xsessions/gnome-classic.desktop"

	# Update manifest
	mkdir -p "$(BUILD)/iso/casper"
	sudo cp "$(BUILD)/chroot/iso/filesystem.manifest" "$(BUILD)/iso/casper/filesystem.manifest"

	# Copy new dists
	sudo rm -rf "$(BUILD)/iso/pool"
	sudo cp -r "$(BUILD)/chroot/iso/pool" "$(BUILD)/iso/pool"

	# Update pool package lists
	sudo rm -rf "$(BUILD)/iso/dists"
	cd $(BUILD)/iso && \
	for pool in $$(ls -1 pool); do \
		mkdir -p "dists/$(UBUNTU_CODE)/$$pool/binary-amd64" && \
		apt-ftparchive packages "pool/$$pool" | gzip > "dists/$(UBUNTU_CODE)/$$pool/binary-amd64/Packages.gz"; \
	done

	# Remove temp directory for modifications
	sudo rm -rf "$(BUILD)/chroot/iso"

	touch "$@"

$(BUILD)/iso_chroot.tag: $(BUILD)/chroot_modify.tag
	# Rebuild filesystem image
	sudo mksquashfs "$(BUILD)/chroot" "$(BUILD)/iso/casper/filesystem.squashfs" -noappend -fstime "$(DISTRO_EPOCH)"

	# Copy vmlinuz, if necessary
	if [ -e "$(BUILD)/chroot/vmlinuz" ]; then \
		sudo cp "$(BUILD)/chroot/vmlinuz" "$(BUILD)/iso/casper/vmlinuz.efi"; \
	fi

	# Rebuild initrd, if necessary
	if [ -e "$(BUILD)/chroot/initrd.img" ]; then \
		sudo gzip -dc "$(BUILD)/chroot/initrd.img" | lzma -7 > "$(BUILD)/iso/casper/initrd.lz"; \
	fi

	# Update filesystem size
	sudo du -sx --block-size=1 "$(BUILD)/chroot" | cut -f1 > "$(BUILD)/iso/casper/filesystem.size"

	sudo chown -R "$(USER):$(USER)" "$(BUILD)/iso/casper"

	touch "$@"

$(BUILD)/iso_modify.tag: $(BUILD)/iso_chroot.tag
	git submodule update --init data/default-settings

	sed "$(SED)" "data/README.diskdefines" > "$(BUILD)/iso/README.diskdefines"

	# Replace disk info
	rm -rf "$(BUILD)/iso/.disk"
	mkdir -p "$(BUILD)/iso/.disk"
	sed "$(SED)" "data/disk/base_installable" > "$(BUILD)/iso/.disk/base_installable"
	sed "$(SED)" "data/disk/casper-uuid-generic" > "$(BUILD)/iso/.disk/casper-uuid-generic"
	sed "$(SED)" "data/disk/cd_type" > "$(BUILD)/iso/.disk/cd_type"
	sed "$(SED)" "data/disk/info" > "$(BUILD)/iso/.disk/info"
	sed "$(SED)" "data/disk/release_notes_url" > "$(BUILD)/iso/.disk/release_notes_url"

	# Replace preseeds
	rm -rf "$(BUILD)/iso/preseed"
	mkdir -p "$(BUILD)/iso/preseed"
	sed "$(SED)" "data/preseed.seed" > "$(BUILD)/iso/preseed/$(DISTRO_CODE).seed"

	# Copy filesystem.manifest-remove
	cp "data/casper/filesystem.manifest-remove" "$(BUILD)/iso/casper/filesystem.manifest-remove"
	cp "data/casper/filesystem.squashfs.gpg" "$(BUILD)/iso/casper/filesystem.squashfs.gpg"

	# Update grub config
	rm -rf "$(BUILD)/iso/boot/grub"
	mkdir -p "$(BUILD)/iso/boot/grub"
	sed "$(SED)" "data/grub/grub.cfg" > "$(BUILD)/iso/boot/grub/grub.cfg"
	sed "$(SED)" "data/grub/loopback.cfg" > "$(BUILD)/iso/boot/grub/loopback.cfg"

	# Copy grub theme
	cp -r "data/default-settings/usr/share/grub/themes" "$(BUILD)/iso/boot/grub/themes"

	touch "$@"

$(BUILD)/iso_sum.tag: $(BUILD)/iso_modify.tag
	# Calculate md5sum
	cd "$(BUILD)/iso" && \
	rm -f md5sum.txt && \
	find -type f -print0 | sort -z | xargs -0 md5sum > md5sum.txt

	touch "$@"

$(BUILD)/$(DISTRO_CODE).tar: $(BUILD)/iso_sum.tag
	tar --create \
		--mtime="@$(DISTRO_EPOCH)" --sort=name \
	    --owner=0 --group=0 --numeric-owner --mode='a=,u+rX' \
	    --file "$@.partial" --directory "$(BUILD)/iso" .

	mv "$@.partial" "$@"

$(BUILD)/$(DISTRO_CODE).iso: $(BUILD)/iso_sum.tag
	grub-mkrescue "$(BUILD)/iso" -o "$@.partial"

	mv "$@.partial" "$@"

$(BUILD)/$(DISTRO_CODE).iso.zsync: $(BUILD)/$(DISTRO_CODE).iso
	cd "$(BUILD)" && zsyncmake -o "`basename "$@.partial"`" "`basename "$<"`"

	mv "$@.partial" "$@"

$(BUILD)/SHA256SUMS: $(BUILD)/$(DISTRO_CODE).iso
	cd "$(BUILD)" && sha256sum -b "`basename "$<"`" > "`basename "$@.partial"`"

	mv "$@.partial" "$@"

$(BUILD)/SHA256SUMS.gpg: $(BUILD)/SHA256SUMS
	cd "$(BUILD)" && gpg --batch --yes --output "`basename "$@.partial"`" --detach-sig "`basename "$<"`"

	mv "$@.partial" "$@"
