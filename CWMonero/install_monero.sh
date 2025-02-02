#!/bin/bash -v

SOURCE_DIR=`pwd`
EXTERNAL_DIR_PATH="$SOURCE_DIR/External"
EXTERNAL_UTILS_DIR_PATH="`pwd`/../SharedExternal/libs"
EXTERNAL_SOURCES_DIR_PATH="$SOURCE_DIR/../SharedExternal"
BOOST_DIR_PATH="$EXTERNAL_UTILS_DIR_PATH/boost"
OPEN_SSL_DIR_PATH="$EXTERNAL_UTILS_DIR_PATH/OpenSSL"
MONERO_CORE_URL="https://github.com/hyle-team/monero-gui.git"
MONERO_CORE_DIR_PATH="$EXTERNAL_DIR_PATH/monero-gui"
MONERO_URL="https://github.com/hyle-team/monero.git"
MONERO_DIR_PATH="$MONERO_CORE_DIR_PATH/monero"
SODIUM_LIBRARY_PATH="$EXTERNAL_UTILS_DIR_PATH/sodium/lib/libsodium.a"
SODIUM_INCLUDE_PATH="$EXTERNAL_UTILS_DIR_PATH/sodium/include"

if [ -z "$EXTERNAL_LIBS_PATH"]
then
  EXTERNAL_LIBS_PATH=$EXTERNAL_UTILS_DIR_PATH
fi

EXTERNAL_MONERO_LIB_PATH="$EXTERNAL_LIBS_PATH/monero/libs"
EXTERNAL_MONERO_INCLUDE_PATH="$EXTERNAL_LIBS_PATH/monero/include"

echo "Export Boost vars"
export BOOST_LIBRARYDIR="${BOOST_DIR_PATH}/build/ios"
export BOOST_LIBRARYDIR_x86_64="${BOOST_DIR_PATH}/build/libs/x86_64"
export BOOST_INCLUDEDIR="${BOOST_DIR_PATH}/include"
echo "Export OpenSSL vars"
export OPENSSL_INCLUDE_DIR="${OPEN_SSL_DIR_PATH}/include"
export OPENSSL_ROOT_DIR="${OPEN_SSL_DIR_PATH}/lib"
export SODIUM_LIBRARY=$SODIUM_LIBRARY_PATH
export SODIUM_INCLUDE=$SODIUM_INCLUDE_PATH
echo "Cloning monero-gui from - $MONERO_CORE_URL"		
git clone -b build $MONERO_CORE_URL $MONERO_CORE_DIR_PATH		
echo "Cloning monero from - $MONERO_URL to - $MONERO_DIR_PATH"		
git clone -b build $MONERO_URL $MONERO_DIR_PATH
cd $MONERO_DIR_PATH
git submodule update --init --force
mkdir -p build
cd ..
./ios_get_libwallet.api.sh
echo "Copy dependencies"
mkdir -p $EXTERNAL_MONERO_LIB_PATH
mkdir -p $EXTERNAL_MONERO_LIB_PATH/lib-ios
mkdir -p $EXTERNAL_MONERO_LIB_PATH/lib
mkdir -p $EXTERNAL_MONERO_LIB_PATH/lib-x86_64
mkdir -p $EXTERNAL_MONERO_INCLUDE_PATH
mkdir -p $EXTERNAL_MONERO_INCLUDE_PATH/src
mkdir -p $EXTERNAL_MONERO_INCLUDE_PATH/external
mkdir -p $EXTERNAL_MONERO_INCLUDE_PATH/contrib

mv $MONERO_DIR_PATH/lib-ios/* $EXTERNAL_MONERO_LIB_PATH/lib-ios/
mv $MONERO_DIR_PATH/lib/* $EXTERNAL_MONERO_LIB_PATH/lib/
mv $MONERO_DIR_PATH/lib-x86_64/* $EXTERNAL_MONERO_LIB_PATH/lib-x86_64/
mv $MONERO_DIR_PATH/src/* $EXTERNAL_MONERO_INCLUDE_PATH/src
mv $MONERO_DIR_PATH/external/* $EXTERNAL_MONERO_INCLUDE_PATH/external
mv $MONERO_DIR_PATH/contrib/* $EXTERNAL_MONERO_INCLUDE_PATH/contrib