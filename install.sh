##########################################################################################
#
# Magisk Module Installer Script
#
##########################################################################################
##########################################################################################
#
# Instructions:
#
# 1. Place your files into system folder (delete the placeholder file)
# 2. Fill in your module's info into module.prop
# 3. Configure and implement callbacks in this file
# 4. If you need boot scripts, add them into common/post-fs-data.sh or common/service.sh
# 5. Add your additional or modified system properties into common/system.prop
#
##########################################################################################

##########################################################################################
# Config Flags
##########################################################################################

# Set to true if you do *NOT* want Magisk to mount
# any files for you. Most modules would NOT want
# to set this flag to true
SKIPMOUNT=false

# Set to true if you need to load system.prop
PROPFILE=false

# Set to true if you need post-fs-data script
POSTFSDATA=false

# Set to true if you need late_start service script
LATESTARTSERVICE=false

##########################################################################################
# Replace list
##########################################################################################

# List all directories you want to directly replace in the system
# Check the documentations for more info why you would need this

# Construct your list in the following format
# This is an example
REPLACE_EXAMPLE="
/system/app/Youtube
/system/priv-app/SystemUI
/system/priv-app/Settings
/system/framework
"

# Construct your own list here
REPLACE="
"

##########################################################################################
#
# Function Callbacks
#
# The following functions will be called by the installation framework.
# You do not have the ability to modify update-binary, the only way you can customize
# installation is through implementing these functions.
#
# When running your callbacks, the installation framework will make sure the Magisk
# internal busybox path is *PREPENDED* to PATH, so all common commands shall exist.
# Also, it will make sure /data, /system, and /vendor is properly mounted.
#
##########################################################################################
##########################################################################################
#
# The installation framework will export some variables and functions.
# You should use these variables and functions for installation.
#
# ! DO NOT use any Magisk internal paths as those are NOT public API.
# ! DO NOT use other functions in util_functions.sh as they are NOT public API.
# ! Non public APIs are not guranteed to maintain compatibility between releases.
#
# Available variables:
#
# MAGISK_VER (string): the version string of current installed Magisk
# MAGISK_VER_CODE (int): the version code of current installed Magisk
# BOOTMODE (bool): true if the module is currently installing in Magisk Manager
# MODPATH (path): the path where your module files should be installed
# TMPDIR (path): a place where you can temporarily store files
# ZIPFILE (path): your module's installation zip
# ARCH (string): the architecture of the device. Value is either arm, arm64, x86, or x64
# IS64BIT (bool): true if $ARCH is either arm64 or x64
# API (int): the API level (Android version) of the device
#
# Availible functions:
#
# ui_print <msg>
#     print <msg> to console
#     Avoid using 'echo' as it will not display in custom recovery's console
#
# abort <msg>
#     print error message <msg> to console and terminate installation
#     Avoid using 'exit' as it will skip the termination cleanup steps
#
# set_perm <target> <owner> <group> <permission> [context]
#     if [context] is empty, it will default to "u:object_r:system_file:s0"
#     this function is a shorthand for the following commands
#       chown owner.group target
#       chmod permission target
#       chcon context target
#
# set_perm_recursive <directory> <owner> <group> <dirpermission> <filepermission> [context]
#     if [context] is empty, it will default to "u:object_r:system_file:s0"
#     for all files in <directory>, it will call:
#       set_perm file owner group filepermission context
#     for all directories in <directory> (including itself), it will call:
#       set_perm dir owner group dirpermission context
#
##########################################################################################
##########################################################################################
# If you need boot scripts, DO NOT use general boot scripts (post-fs-data.d/service.d)
# ONLY use module scripts as it respects the module status (remove/disable) and is
# guaranteed to maintain the same behavior in future Magisk releases.
# Enable boot scripts by setting the flags in the config section above.
##########################################################################################

# Set what you want to display when installing your module

print_modname() {
  ui_print "*************************************"
  ui_print "  libsecure_storage companion v2.0  *"
  ui_print "*************************************"
}

# Copy/extract your module files into $MODPATH in on_install.

on_install() {
  # The following is the default implementation: extract $ZIPFILE/system to $MODPATH
  # Extend/change the logic to whatever you want
  ui_print "- Extracting module files"
  unzip -o "$ZIPFILE" 'system/*' -d $MODPATH >&2

  display_os_ver
  install_mod
}

# Only some special files require specific permissions
# This function will be called after on_install is done
# The default permissions should be good enough for most cases

set_permissions() {
  # The following is the default rule, DO NOT remove
  set_perm_recursive $MODPATH 0 0 0755 0644

  # Here are some examples:
  # set_perm_recursive  $MODPATH/system/lib       0     0       0755      0644
  # set_perm  $MODPATH/system/bin/app_process32   0     2000    0755      u:object_r:zygote_exec:s0
  # set_perm  $MODPATH/system/bin/dex2oat         0     2000    0755      u:object_r:dex2oat_exec:s0
  # set_perm  $MODPATH/system/lib/libart.so       0     0       0644
}

# You can add more functions to assist your custom script code

display_os_ver() {
  os=$(getprop ro.build.version.release)
  major=${os%%.*}
  local bl=$(getprop ro.boot.bootloader)

  # Firmware version starts at either 8th or 9th character, depending on length
  # of bootloader string (12 or 13).
  #
  local fw=${bl:$((${#bl} - 4)):4}

  # Device is either 4 or 5 characters long, depending on length of
  # bootloader string.
  #
  device=${bl:0:$((${#bl} - 8))}

  ui_print ""
  ui_print "- This Android $os device is a $device running $fw firmware,"
  ui_print ""
}

patch_libbluetooth() {
  [ $major -ne 10 ] && return

  local f=$mirror/system/lib64/libbluetooth.so
  local tf=$MODPATH/system/lib64/libbluetooth.so

  ui_print "- Attempting to patch $f...This may take a while."
  mkdir -p ${tf%/*}

  if echo $device | grep -E '[GN]9[67][0356]0|F90(0[FN]|7[BN])|T86[05]' >/dev/null; then
    # Snapdragon based devices, such as Tab S6, Fold (5G) and Chinese S9/10/N9/10.
    #
    substitute='s/88000054691180522925c81a69000037e0030032/04000014691180522925c81a69000037e0031f2a/'
  else
    substitute='s/c8000034f4031f2af3031f2ae8030032/1f2003d5f4031f2af3031f2ae8031f2a/'
  fi

  # /system/bin/xxd must be used for the reconstruction, since Magisk Busybox
  # xxd doesn't support -r for reverse operation.
  xxd -p $f | tr -d '\n ' | sed -e $substitute | /system/bin/xxd -rp > $tf

  if ! cmp $tf $f >/dev/null && [ $(stat -c '%s' $tf) -eq $(stat -c '%s' $f) ]; then
    ui_print "- Patching succeeded."
    touch -r $f $tf
    chmod 644 $tf
    lib=bluetooth
  else
    rm -f $tf
    abort "- Patching failed. No change made."
  fi
}

install_mod() {

  # Real /system can be found here.
  #
  mirror=/sbin/.magisk/mirror
  lib=secure_storage

  if [ -f $mirror/system/lib/libsecure_storage.so ]; then

    if [ $major -eq 10 ]; then

      # 10 or similar: Patch libbluetooth.so.
      rm -rf $MODPATH/system/*
      patch_libbluetooth
    else
      # Pie or similar: Move .so files to /system.
      #
      mv $MODPATH/system/vendor/* $MODPATH/system && rmdir $MODPATH/system/vendor
    fi

    local instdir=/system

  else
    # Oreo or similar: Leave .so files in /vendor.
    #
    local instdir=/vendor
  fi

  ui_print "- When active, the module will mask lib$lib.so in $instdir."
}
