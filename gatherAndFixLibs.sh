#!/bin/bash

# Check if a binary was passed to the script
if [ -z "$1" ]; then
  echo "Usage: $0 <binary>"
  exit 1
fi

# Get the directory of the binary
BINARY_DIR=$(dirname "$1")

# # Create the deps directory if it doesn't exist
DEPS_DIR="$(pwd)/deps"
mkdir -p "$DEPS_DIR"

# Get a list of all dynamic libraries and frameworks used by the binary
DEPENDENCIES=$(otool -L "$1" | grep -v "$1" | grep "@rpath" | awk '{print $1}' | sed 's/@rpath\///')

echo "DEPENDENCIES: $DEPENDENCIES"

# Copy the dependencies to the deps directory
for DEPENDENCY in $DEPENDENCIES; do
  echo "Copying in dep: $DEPENDENCY:"
  DFL=$(locate "$DEPENDENCY" | grep -i iphoneos)

  if [[ $DFL == *"framework"* ]]; then
    echo "Copying in dir $(dirname "$DFL" | head -n 1)"
    cp -r "$(dirname "$DFL" | head -n 1)" "$DEPS_DIR"
  else
    echo "Copying in file $DFL"
    cp -r "$DFL" "$DEPS_DIR"
  fi
done

# for DEPENDENCY_FILE in $DEPS_DIR/*; do
for DEPENDENCY_FILE in $(find $DEPS_DIR/* -type f -perm +111 -exec sh -c 'file {} | head -n 1' \; | grep -E 'Mach-O 64-bit dynamically linked shared library arm64' | sed -n 's|\(^/[^:]*\): Mach-O.*|\1|p'); do
  echo "Cur dep file or dir: $DEPENDENCY_FILE"
  DEPENDENCY=$(basename "$DEPENDENCY_FILE")
  echo "Running: otool -L $DEPENDENCY_FILE"
  DEPENDENCY_DEPS=$(otool -L "$DEPENDENCY_FILE" | grep "@rpath" | awk '{print $1}' | sed 's/@rpath\///' | grep -v "$DEPENDENCY.framework")
  echo "Deps found for $DEPENDENCY_FILE:"
  echo $DEPENDENCY_DEPS

  echo "Copying in deps of deps"
  for DEP in $DEPENDENCY_DEPS; do
    DFL=$(locate "$DEP" | grep -i iphoneos)
    echo "Searching for $DEP for iphone, found $DFL"

    if [[ $DFL == *"framework"* ]]; then
      echo "Copying in dir $(dirname "$DFL" | head -n 1)"
      cp -r "$(dirname "$DFL" | head -n 1)" "$DEPS_DIR"
    else
      echo "Copying in file $DFL"
      cp -r "$DFL" "$DEPS_DIR"
    fi
  done
done

# Set the rpath for each dependency in the deps directory
for DEPENDENCY_FILE in $DEPS_DIR/*; do
  echo "Adding rpath for $DEPENDENCY_FILE"
  install_name_tool -add_rpath "@executable_path/Frameworks" "$DEPENDENCY_FILE"
done

# Set the rpath for the binary to include the deps directory
echo "Adding rpath for original binary"
install_name_tool -add_rpath "@executable_path/Frameworks" "$1"
