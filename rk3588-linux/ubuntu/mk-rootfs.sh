#!/bin/bash -e
chroot_dir=binary  

if [ ! $VERSION ]; then
    VERSION="ubuntu20"
fi

echo -e "\033[36m Building for $VERSION\033[0m"

if [ -d "binary" ]; then
  sudo rm -rf binary
  echo "Deleted binary directory."
fi

echo -e "\033[36m Extract image \033[0m"      
case $VERSION in
    "ubuntu20")
        sudo tar -xf ubuntu-focal-xfce-arm64.tar.xz
        ;;
    "ubuntu22")
        sudo tar -xf ubuntu-jammy-xfce-arm64.tar.xz
        ;;
    *)
        echo "Unsupported version."
        ;;
esac

sudo cp -rfp overlay/* ${chroot_dir}/ || true

# NetworkManager ignores system connection files unless they are locked down.
if [ -d "${chroot_dir}/etc/NetworkManager/system-connections" ]; then
  sudo chown root:root "${chroot_dir}"/etc/NetworkManager/system-connections/* 2>/dev/null || true
  sudo chmod 600 "${chroot_dir}"/etc/NetworkManager/system-connections/* 2>/dev/null || true
fi

sudo mount -t proc /proc ${chroot_dir}/proc
sudo mount -t sysfs /sys ${chroot_dir}/sys
sudo mount -o bind /dev ${chroot_dir}/dev
sudo mount -o bind /dev/pts ${chroot_dir}/dev/pts

sudo chroot "${chroot_dir}" /bin/bash -c "apt update"

sudo umount -lf ${chroot_dir}/dev/pts 2> /dev/null || true
sudo umount -lf ${chroot_dir}/* 2> /dev/null || true
