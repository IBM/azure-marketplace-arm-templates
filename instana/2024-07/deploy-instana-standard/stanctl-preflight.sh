#!/bin/sh

set -o errexit
set -o nounset

main() {
    setup_env

    set_max_user_instances
    set_vm_swappiness
    disable_thp
}

info() {
    echo '[INFO] ' "$@"
}

fatal()
{
    echo '[ERROR] ' "$@" >&2
    exit 1
}

setup_env() {
    # Use sudo if the user is not already root
    SUDO=sudo
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=
    fi
}

set_sysctl_parameter(){
    param=$1
    file_sysctl_stanctl_config="/etc/sysctl.d/99-stanctl.conf"

    if ! $SUDO grep -F -q "$param" "$file_sysctl_stanctl_config"; then
        info "Setting kernel parameter $param"
        $SUDO sh -c "echo '$param' >> $file_sysctl_stanctl_config"
        $SUDO sysctl -p "$file_sysctl_stanctl_config"
    fi
}

set_max_user_instances() {
    n=$($SUDO sysctl fs.inotify.max_user_instances -n)
    if [ "$n" -lt "8192" ]; then
        set_sysctl_parameter "fs.inotify.max_user_instances=8192"
    fi
}

set_vm_swappiness() {
    n=$($SUDO sysctl vm.swappiness -n)
    if [ "$n" != 0 ]; then
        set_sysctl_parameter "vm.swappiness=0"
    fi
}

disable_thp() {
    thp_file="/sys/kernel/mm/transparent_hugepage/enabled"
    if [ ! -f "$thp_file" ]; then
        fatal "Cannot find $thp_file"
    fi

    thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
    if grep -q "\[never\]" "$thp_file"; then
        info "Transparent huge pages are configured as $thp. Already disabled"
        return
    fi

    if [ -f "/etc/debian_version" ] || grep -q "NAME=\"SLES\"" /etc/os-release ; then
        os_type="Debian"
    elif [ -f "/etc/redhat-release" ] || [ -f "/etc/centos-release" ] || [ -f "/etc/fedora-release" ] || [ -f "/etc/amazon-linu
x-release" ]; then
        os_type="CentOS"
    fi

    info "Transparent huge pages are configured as $thp"
    info "Disabling Transparent huge pages"
    $SUDO sh -c "echo never > $thp_file"
    param_thp="transparent_hugepage=never"

    info "Configure grub for $os_type"
    if [ "$os_type" = "Debian" ]; then
        grub_configuration_file="/etc/default/grub"
        if [ -f "$grub_configuration_file" ]; then
            if ! $SUDO grep -F -q "$param_thp" "$grub_configuration_file"; then
                $SUDO sed -i "s/\(GRUB_CMDLINE_LINUX=\".*\)\"/\1 $param_thp\"/" "$grub_configuration_file"

                if command -v update-grub 2>/dev/null; then
                    info "Updating GRUB configuration"
                    $SUDO update-grub
                    info "GRUB configuration updated"
                fi
            fi
        fi
    elif [ "$os_type" = "CentOS" ]; then
        package_installer=yum
        if [ "$package_installer" = "yum" ] && [ -x /usr/bin/dnf ]; then
            package_installer=dnf
        fi

        if ! command -v grubby 2>/dev/null; then
            info "Install grubby with $package_installer"
            $SUDO $package_installer install -q -y grubby
        fi
        $SUDO grubby --args="$param_thp" --update-kernel ALL
    fi
}

main