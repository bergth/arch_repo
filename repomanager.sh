#!/bin/bash

WORK_DIR="/data/archrepo/work"
DEST_DIR="/data/archrepo/dest"
NAME="bergth"

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

echo_mnt_repo()
{
	echo "enter mnt repo"
	if [ "$(grep \[$NAME\] $WORK_DIR/chroot/root/etc/pacman.conf)" == "" ] && [ -f "$DEST_DIR/$NAME.db.tar.gz" ]; then
		echo "add repo"
    		sudo bash -c " echo \"[$NAME]\" >>  \"$WORK_DIR/chroot/root/etc/pacman.conf\""
    		sudo bash -c " echo \"SigLevel = Optional TrustAll\" >> \"$WORK_DIR/chroot/root/etc/pacman.conf\""
    		sudo bash -c "echo \"Server = file:///mnt\"  >> \"$WORK_DIR/chroot/root/etc/pacman.conf\""
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
    echo_mnt_repo
    sudo mount --bind -o ro "$DEST_DIR" "$WORK_DIR/chroot/root/mnt"
    arch-nspawn "$WORK_DIR/chroot/root" pacman -Syu
    sudo umount "$WORK_DIR/chroot/root/mnt"
}


create_database()
{
    if [ ! -f "$WORK_DIR/pkg.db" ]; then
        sqlite3 "$WORK_DIR/pkg.db" \
        "create table lst_pkg (id INTEGER PRIMARY KEY, name TEXT, path TEXT, ver TEXT)"
        sqlite3 "$WORK_DIR/pkg.db" \
        "create table mkf_pkg (id INTEGER PRIMARY KEY, name TEXT, pkg TEXT)"
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

rmv_pkg_repo()
{
    SQLITE=$(sqlite3 "$WORK_DIR/pkg.db" "select pkg from mkf_pkg where name = '$1'");
    if [ "$SQLITE" != "" ]; then
        cd "$DEST_DIR"
        while read e; do
            PRNAME="$(pacman -Q --info -p $e | grep Name | cut -d: -f 2 | tr -d '[:space:]')"
            repo-remove "./$NAME.db.tar.gz" "$PRNAME"
        done <<< $SQLITE
    fi
    sqlite3 "$WORK_DIR/pkg.db" "delete from mkf_pkg where name = '$1'";
}


rmv_pkg()
{
    PWORKDIR=$(sqlite3 "$WORK_DIR/pkg.db" "select distinct path from lst_pkg where name = '$1'")
    if [ "$PWORKDIR" != "" ]; then
        sqlite3 "$WORK_DIR/pkg.db" "delete from lst_pkg where name = '$1'";
        rmv_pkg_repo $1
        rm -rf $WORK_DIR/$PWORKDIR
    else
        echo "!! Your package is not in AUR work directory !!"
        exit 1
    fi
}


make_pkg()
{
    PWORKDIR=$(sqlite3 "$WORK_DIR/pkg.db" "select distinct path from lst_pkg where name = '$1'")

    if [ "$WORK_DIR/$PWORKDIR" != "" ]; then
        cd "$WORK_DIR/$PWORKDIR"
        ACVER=$(get_pkgbuild_version $WORK_DIR/$PWORKDIR)
        makechrootpkg -D "$DEST_DIR/:/mnt"  -c -r "$WORK_DIR/chroot"
        LIST_PKGXZ="$(ls -1 *.pkg.tar.xz)"
        
        rmv_pkg_repo $1
        while read e; do
            echo "add $e"
            cd "$WORK_DIR/$PWORKDIR"
            cp "$e" "$DEST_DIR"
            cd "$DEST_DIR"
            repo-add "./$NAME.db.tar.gz" "$e"
            sqlite3 "$WORK_DIR/pkg.db" "insert into mkf_pkg(name,pkg) values ('$1', '$e')"
        done <<< "$LIST_PKGXZ"

        sqlite3 "$WORK_DIR/pkg.db" "update lst_pkg set ver = '$ACVER' where name = '$1'"


    else
        echo "!! Your package is not in work directory !!"
        exit 1
    fi
}

list_pkg()
{
    SQLITE=$(sqlite3 "$WORK_DIR/pkg.db" "select * from lst_pkg");
    if [ "$SQLITE" == "" ]; then
        echo "Database is empty"
    else
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
    fi
}

update_needed()
{
    PPATH=$(sqlite3 "$WORK_DIR/pkg.db" "select distinct path from lst_pkg where name = '$1'")
    LBVER=$(sqlite3 "$WORK_DIR/pkg.db" "select distinct ver from lst_pkg where name = '$1'")
    if [ "$LBVER" == "" ]; then
        echo "1"
    else
        ACVER=$(get_pkgbuild_version "$WORK_DIR/$PPATH")
        if [ "$(vercmp $ACVER $LBVER) " -gt "0" ]; then
            echo "1"
        else
            echo "0"
        fi
    fi
}

make_all()
{
    SQLITE=$(sqlite3 "$WORK_DIR/pkg.db" "select * from lst_pkg");
    if [ "$SQLITE" == "" ]; then
        echo "Database is empty"
    else
        ARRAY=()
        while read e; do
            PNAME=$(echo $e | cut -d\| -f 2)
            PWDIR=$(echo $e | cut -d\| -f 3)
            LBVER=$(echo $e | cut -d\| -f 4)
            ACVER=$(get_pkgbuild_version "$WORK_DIR/$PWDIR")
            if [ "$(update_needed $PNAME)" -gt "0" ]; then
                echo "*----------------------------------------------*"
                echo " + $PNAME"
                echo "     => work directory: [$WORK_DIR/$PWDIR]"
                echo "     => Last build version: [$LBVER]"
                echo "     => Version in work dir: [$ACVER]"
                ARRAY+=("$PNAME")
            fi 
        done <<< "$SQLITE"
        echo "*----------------------------------------------*"
        echo "Need to update: "
        echo "    => ${ARRAY[*]}"
        read -p "go ? " valid
        if [ "$valid" == "y" ]; then
            for i in "${ARRAY[@]}"; do
                echo "!! Update $i !!"
                make_pkg $i
            done
        fi
    fi
}



test_and_mkdir
init_chroot
#echo_mnt_repo
create_database
update_chroot

if [ "$1" == "addaur" ] && [ "$2 " != "" ]; then
    aur_add_pkg "$2"
elif  [ "$1" == "rmv" ] && [ "$2 " != "" ]; then
    rmv_pkg "$2"
elif  [ "$1" == "make" ]; then
    make_all
else
    echo "Check param"
fi

repo-elephant
