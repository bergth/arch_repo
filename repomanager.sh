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
        exit 1
    fi

    if [ -d "$WORK_DIR/AUR/$1" ]; then
        echo "!! Your package already exist in AUR work directory !!"
        exit 1
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
    else
        echo "!! Your package is not in AUR work directory !!"
        exit 1
    fi
}

get_pkgbuild_version()
{
    PKGVER=$(grep "pkgver=" "$1/PKGBUILD" | cut -d= -f 2)
    PKGREL=$(grep "pkgrel=" "$1/PKGBUILD" | cut -d= -f 2)
    EPOCH=$(grep "epoch=" "$1/PKGBUILD" | cut -d= -f 2)

    FINAL=""
    if [ "$EPOCH" != "" ]; then
        FINAL="$EPOCH:"
    fi
    FINAL="$FINAL$PKGVER"
    if [ "$PKGREL" != "" ]; then
        FINAL="$FINAL-$PKGREL"
    fi
    echo "$FINAL"
}

make_pkg()
{
    PWORKDIR=$(sqlite3 "$WORK_DIR/pkg.db" "select distinct path from lst_pkg where name = '$1'")

    if [ "$WORK_DIR/$PWORKDIR" == "" ]; then
        cd "$WORK_DIR/$1"
        $ACVER = get_pkgbuild_version $WORK_DIR/$1
        makechrootpkg -c -r "$WORK_DIR/chroot"
        sqlite3 "$WORK_DIR/pkg.db" "update lst_pkg set ver = '$ACVER' where name = '$1'"
    else
        echo "!! Your package is not in work directory !!"
        exit 1
    fi
}

list_pkg()
{
    SQLITE=$(sqlite3 "$WORK_DIR/pkg.db" "select * from lst_pkg");
    
    while read e; do
        PNAME=$(echo $e | cut -d\| -f 2)
        PWDIR=$(echo $e | cut -d\| -f 3)
        LBVER=$(echo $e | cut -d\| -f 4)
        ACVER=$(get_pkgbuild_version "$WORK_DIR/$PWDIR")
        echo "*----------------------------------------------*"
        echo " + $PNAME"
        echo "     => work directory: [$WORK_DIR/$PWDIR]"
        echo "     => Last build version: [$LBVER]"
        echo "     => Version in work dir: [$ACVER]"
    done <<< "$SQLITE"
    echo "*----------------------------------------------*"
}




#test_and_mkdir
#init_chroot
#create_database
#update_chroot
#aur_add_pkg "gogs"
#make_pkg AUR/google-chrome

list_pkg
make_pkg google-chrome
list_pkg

#get_pkgbuild_version "$WORK_DIR/AUR/google-chrome"
#get_pkgbuild_version "$WORK_DIR/AUR/gogs"

