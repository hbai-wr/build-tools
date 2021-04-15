#!/bin/bash

HELP=0
PKG_PATH=""
BUILD_PATH=""
PKG_NAME=""
DL_CMD=wget

usage () {
    echo ""
    echo "Usage: "
    echo "   Create(Repackage) xxx.tar.xz, xx.dsc, xx.debian.tar.xz(diff.gz) "
}

get_deb_ver () {
    local deb_ver_file=$1

    while read line
    do
        echo $line | grep "^#" > /dev/null 2>&1
        [ $? == 0 ] && continue
        if [ x"$line" != x ]; then
            echo $line
            return
        fi
    done < $deb_ver_file

    echo "None"
    return 0
}

get_deb_files () {
    local real_name=$1
    local major_ver=$2
    local file_ver=$3
    local deb_fmt=$4
    local dsc_file=""
    local src_dir=""
    local tar_file=""
    local deb_tar=""

    fmt_ver=`cat $deb_fmt | awk '{print $1}'`
    fmt_typ=`cat $deb_fmt | awk '{print $2}'`

    dsc_file=$real_name"_"$file_ver.dsc
    src_dir=$real_name-$major_ver

    if [ $fmt_ver == "1.0" ]; then
        tar_file=$real_name"_"$major_ver.orig.tar.gz
        deb_tar=$real_name"_"$file_ver.diff.gz
    else
        if  [[ $fmt_typ =~ "native" ]]; then
            tar_file=$real_name"_"$file_ver.tar.xz
            deb_tar=""
        else
            tar_file=$real_name"_"$major_ver.orig.tar.gz
            deb_tar=$real_name"_"$file_ver.debian.tar.xz
        fi
    fi

    echo $src_dir $dsc_file $tar_file $deb_tar
}

update_deb_folder() {
    local src_dir=$1
    local deb_dir=$2

    if [ -d $deb_dir/meta_data ]; then
        #echo "Update the debian folder ..."
        [ ! -d $src_dir/debian ] && mkdir -p $src_dir/debian
        cp -r $deb_dir/meta_data/* $src_dir/debian
    fi

    deb_fmt="$deb_dir/meta_data/source/format"
    fmt_ver=`cat $deb_fmt | awk '{print $1}'`
    fmt_typ=`cat $deb_fmt | awk '{print $2}'`

    if [ $fmt_ver == "1.0" ]; then
        if [ -f $deb_dir/patches/series ]; then
            for i in `cat $deb_dir/patches/series`; do
                #echo "Apply patch $i"
                (cd $src_dir; patch -p1 < $deb_dir/patches/$i >/dev/null 2>&1)
            done
        fi
    fi
}

repack_deb_pkg () {
    local real_name=$1
    local deb_ver=$2
    local major_ver=$3
    local deb_fmt=$4
    local src_dir=$5
    local tis_ver="tis"
    local dsc_file=""
    local tar_file=""
    local deb_tar=""

    #echo "Repackage ..."
    bld_log=$(cd $src_dir/../;pwd)/$real_name-$major_ver.log
    cd $src_dir;dpkg-buildpackage -us -uc -S -d > $bld_log 2>&1
    if [ $? != 0 ]; then
        echo "Fail to build $real_name, log is at $bld_log"
        exit 1
    fi
    
    fmt_ver=`cat $deb_fmt | awk '{print $1}'`
    fmt_typ=`cat $deb_fmt | awk '{print $2}'`

    dsc_file=$real_name"_"$deb_ver.$tis_ver.dsc

    if [ $fmt_ver == "1.0" ]; then
        tar_file=$real_name"_"$major_ver.orig.tar.gz
        deb_tar=$real_name"_"$deb_ver.$tis_ver.diff.gz
    else
        if [[ $fmt_typ =~ "native" ]]; then
            tar_file=$real_name"_"$deb_ver.$tis_ver.tar.xz
            deb_tar=""
        else
            tar_file=$real_name"_"$major_ver.orig.tar.gz
            deb_tar=$real_name"_"$deb_ver.$tis_ver.debian.tar.xz
        fi
    fi
    echo $dsc_file $tar_file $deb_tar
}

extract_pkg () {
    local tar_pkg=$1
    local tar_cmd=""

    case $tar_pkg in
        *.tar.gz) tar_cmd="tar -xf" ;;
        *.tgz)    tar_cmd="tar -xzf" ;;
        *.tar.bz2) tar_cmd="tar -xjf" ;;
        *.tar.xz)  tar_cmd="tar -xJf" ;;
        *.tar)     tar_cmd="tar -xf" ;;
        *)         echo "skipping '$tar_pkg'" ;;
    esac
    $tar_cmd $tar_pkg
}

# read the options
ARGS=$(getopt -o h --long build-path:,pkg-path:,help -n 'create_sdebpkg.sh' -- "$@")
if [ $? -ne 0 ]; then
    usage
    exit 1
fi
eval set -- "${ARGS}"
while true; do
    case "$1" in
        --pkg-path)     PKG_PATH=$2 ; shift 2;;
        --build-path)     BUILD_PATH=$2 ; shift 2;;
        -h|--help)        HELP=1 ; shift ;;
        --)               shift ; break ;;
        *)                usage; exit 1 ;;
    esac
done

if [ $HELP -eq 1 ]; then
    usage
    exit 0
fi

if [ ! -d $PKG_PATH ]; then
    echo "$PKG_PATH, No such directory"
    exit 1
fi

if [ ! -d $BUILD_PATH ]; then
    echo "$BUILD_PATH, No such directory"
    exit 1
fi

PKG_PATH=`cd $PKG_PATH;pwd`
BUILD_PATH=`cd $BUILD_PATH;pwd`
PKG_NAME=$(basename $PKG_PATH)
REAL_NAME=$PKG_NAME
DEB_DIR=$PKG_PATH/debian

if [ ! -d $DEB_DIR ]; then
    echo "$PKG_NAME doesn't have debian folder"
    exit 1
fi

if [ ! -f $DEB_DIR/debver ]; then
    echo "No \"debian/debver\" file"
    exit 1
else
    DEB_VER=`get_deb_ver $DEB_DIR/debver`
    if [ $DEB_VER == "None" ]; then
        echo "No package version defined in \"debian/debver\""
        exit 1
    fi
fi

MAJOR_VER=${DEB_VER%-*}
#some packages version like 2.1.12-stable-1(libevent), the folder is libevent-2.1.12-stable
MINOR_VER=${DEB_VER##*-}
#some packages verion like 1:4.7.0-1(cluster-resource-agents), the folder is pkgname-4.7.0
MAJOR_VER=${MAJOR_VER##*:}
FILE_VER=${DEB_VER##*:}

if [ -f $DEB_DIR/debname ]; then
    REAL_NAME=`cat $DEB_DIR/debname`
fi

if [ -f $DEB_DIR/dl_path ]; then
    URL=`cat $DEB_DIR/dl_path`
    TAR_FILE=`basename $URL`
    if [ -f $BUILD_PATH/$TAR_FILE ]; then
        rm $BUILD_PATH/$TAR_FILE
    fi
    (cd $BUILD_PATH; 
     $DL_CMD $URL >/dev/null 2>&1
     extract_pkg $TAR_FILE)
    TAR_NAME=`tar -tzf $BUILD_PATH/$TAR_FILE | head -1 | cut -f1 -d"/"`

    FULL_NAME="$REAL_NAME-$MAJOR_VER"
    if [ x"$FULL_NAME" != x"$TAR_NAME" ]; then
        (cd $BUILD_PATH; 
         [ -d $FULL_NAME ] && rm -r $FULL_NAME
         mv $TAR_NAME $FULL_NAME)
    fi
    (cd $BUILD_PATH;tar czf $REAL_NAME"_"$MAJOR_VER.orig.tar.gz $FULL_NAME; rm -r $TAR_FILE)
    SRC_DIR="$BUILD_PATH/$FULL_NAME"
elif [ -f $DEB_DIR/src_path ]; then
    SRC_DIR=`cat $DEB_DIR/src_path`
    if [ ! -d $PKG_PATH/$SRC_DIR ]; then
        echo "No source dir $PKG_PATH/$SRC_DIR"
        exit 1
    fi
    TRG_DIR=$SRC_DIR-$MAJOR_VER
    [ -d $BUILD_PATH/$TRG_DIR ] && rm -r $BUILD_PATH/$TRG_DIR
    cp -r $PKG_PATH/$SRC_DIR $BUILD_PATH/$TRG_DIR
    SRC_DIR="$BUILD_PATH/$TRG_DIR"
else
    SUPPORTED_VERS=`apt-cache madison $REAL_NAME | grep "Sources" | awk -F"|" '{print $2}'`
    echo "$SUPPORTED_VERS" | grep "$DEB_VER" >/dev/null 2>&1
    if [ $? == 0 ]; then
        DEB_FILES=`get_deb_files $REAL_NAME $MAJOR_VER $FILE_VER "$DEB_DIR/meta_data/source/format"`
        if [ "$DEB_FILES" != "" ]; then
            #echo "Removing the existing sources codes ..."
            (cd $BUILD_PATH; rm -rf $DEB_FILES)
        fi
        #echo "Downloading the sources codes ..."
        (cd $BUILD_PATH;apt source $REAL_NAME=$DEB_VER >/dev/null 2>&1)
        DEB_FILES=(${DEB_FILES// / })
        SRC_DIR="$BUILD_PATH/${DEB_FILES[0]}"
        #FIXME, force removing the sign file
        (cd $BUILD_PATH; rm *.orig.tar.gz.asc)
    else
        echo "No \"$REAL_NAME-$DEB_VER\", the available versions are:"
        echo "$SUPPORTED_VERS"
        exit 1
    fi
fi

update_deb_folder "$SRC_DIR" "$DEB_DIR"
repack_deb_pkg $REAL_NAME $FILE_VER $MAJOR_VER "$DEB_DIR/meta_data/source/format" "$SRC_DIR"

exit 0
