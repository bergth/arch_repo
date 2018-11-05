#!/bin/bash

WORK_DIR="$HOME/archrepo/work"
DEST_DIR="$HOME/archrepo/dest"


set -e 

test_and_mkdir()
{
    if [ ! -d "$WORK_DIR" ]; then
        mkdir -p "$WORK_DIR"

    fi

    if [ ! -d "$DEST_DIR" ]; then
        mkdir -p "$DEST_DIR"
    fi
}

init_chroot()
{
    if [ ! -d "$WORK_DIR/chroot" ]; then
        mkdir "$WORK_DIR/chroot"
        mkarchroot "$WORK_DIR/chroot/root" base-devel
    fi
}

update_chroot()
{
    arch-nspawn "$WORK_DIR/chroot/root" pacman -Syu
}


create_database()
{
    if [ ! -f "$WORK_DIR/pkg.db" ]; then
        sqlite3 "$WORK_DIR/pkg.db" \
        "create table lst_pkg (id INTEGER PRIMARY KEY, name TEXT, path TEXT, ver TEXT)"
    fi  
}

aur_add_pkg()
{

    if [ "$(git ls-remote https://aur.archlinux.org/$1.git)" == "" ]; then 
        echo "!! I can't found your package in AUR !!"
        exit 0
    fi

    if [ -d "$WORK_DIR/AUR/$1" ]; then
        echo "!! Your package already exist in AUR work directory !!"
        exit 0
    fi

    mkdir -p "$WORK_DIR/AUR/$1"
    git clone "https://aur.archlinux.org/$1.git" "$WORK_DIR/AUR/$1"

    sqlite3 "$WORK_DIR/pkg.db" "insert into lst_pkg(name, path, ver) values ('$1', 'AUR/$1', null)"
    
}

aur_rmv_pkg()
{
    if [ -d "$WORK_DIR/AUR/$1" ]; then
        sqlite3 "$WORK_DIR/pkg.db" "delete from lst_pkg where name = '$1'";
        rm -rf $WORK_DIR/AUR/$1
    fi
}

test_and_mkdir
init_chroot
create_database
update_chroot
aur_rmv_pkg "google-chrome"


