#!/bin/sh

# brew install cmake
# brew install boost
# brew install rabbitmq

# Sanity checks for cmake, git and boost
LIB_DIR=/usr/local/lib
BREW_DIR=/usr/local/Cellar

# Boost
if [ ! -f $LIB_DIR/libboost_context.a ] && [ ! -d $BREW_DIR/boost ] 
then
	echo "boost missing: tried $LIB_DIR and $BREW_DIR"
	exit -1
fi

# cmake
cmake --version >/dev/null
if [[ $? != 0 ]] ; then
	echo "cmake not installed."
	exit -1
fi

# Build the C code
cd rabbitmq-c
mkdir build
cd build
cmake .. -DBUILD_STATIC_LIBS=true
cmake --build .
cmake --build . --target install
cd ../..

# Build the CPP code
cd rabbitmq-cpp
mkdir build
cd build
cmake .. -DBUILD_SHARED_LIBS=false 
cmake --build .
cmake --build . --target install
cd ../..

# Build the image recognition module
cd recog
mkdir build
cd build
cmake .. 
cmake --build .
ctest -VV
cd ../..

