#!/bin/bash

set -e

cd $GOPATH/src/github.com/fstab/grok_exporter

export VERSION=0.2.2-SNAPSHOT

export VERSION_FLAGS="\
        -X github.com/fstab/grok_exporter/exporter.Version=$VERSION
        -X github.com/fstab/grok_exporter/exporter.BuildDate=$(date +%Y-%m-%d)
        -X github.com/fstab/grok_exporter/exporter.Branch=$(git rev-parse --abbrev-ref HEAD)
        -X github.com/fstab/grok_exporter/exporter.Revision=$(git rev-parse --short HEAD)
"

#--------------------------------------------------------------
# Helper functions
#--------------------------------------------------------------

function enable_legacy_static_linking {
    # The compile script in the Docker image sets CGO_LDFLAGS to libonig.a, which should make grok_exporter
    # statically linked with the Oniguruma library. However, this doesn't work on Darwin and CentOS 6.
    # As a workaround, we set LDFLAGS directly in the header of oniguruma.go.
    sed -i.bak 's;#cgo LDFLAGS: -L/usr/local/lib -lonig;#cgo LDFLAGS: /usr/local/lib/libonig.a;' exporter/oniguruma.go
}

function revert_legacy_static_linking {
    if [ -f exporter/oniguruma.go.bak ] ; then
        mv exporter/oniguruma.go.bak exporter/oniguruma.go
    fi
}

# Make sure revert_legacy_static_linking is called even if a compile error makes this script terminate early
trap revert_legacy_static_linking EXIT

function create_zip_file {
    OUTPUT_DIR=$1
    cp -a logstash-patterns-core/patterns dist/$OUTPUT_DIR
    cp -a example dist/$OUTPUT_DIR
    cd dist
    sed -i.bak s,/logstash-patterns-core/patterns,/patterns,g $OUTPUT_DIR/example/*.yml
    rm $OUTPUT_DIR/example/*.yml.bak
    zip --quiet -r $OUTPUT_DIR.zip $OUTPUT_DIR
    rm -r $OUTPUT_DIR
    cd ..
}

# Build grok exporter under centos
function run_docker_linux_amd64 {
    docker run \
        -v $GOPATH/src/github.com/fstab/grok_exporter:/root/go/src/github.com/fstab/grok_exporter \
        --net none \
        --rm -ti fstab/grok_exporter-compiler-amd64 \
        ./compile-linux.sh -ldflags "$VERSION_FLAGS" -o "dist/grok_exporter-$VERSION.linux-amd64/grok_exporter"
}

# Build grok exporter under ubuntu
function run_docker_linux_arm64v8 {
    docker run \
        -v $GOPATH/src/github.com/fstab/grok_exporter:/root/go/src/github.com/fstab/grok_exporter \
        --net none \
        --rm -ti fstab/grok_exporter-compiler-arm64v8 \
        ./compile-linux.sh -ldflags "$VERSION_FLAGS" -o "dist/grok_exporter-$VERSION.linux-arm64v8/grok_exporter"
}

#--------------------------------------------------------------
# Release functions
#--------------------------------------------------------------

function release_linux_amd64 {
    echo "Building dist/grok_exporter-$VERSION.linux-amd64.zip"
    enable_legacy_static_linking
    run_docker_linux_amd64
    revert_legacy_static_linking
    #create_zip_file grok_exporter-$VERSION.linux-amd64
}

function release_linux_arm64v8 {
    echo "Building dist/grok_exporter-$VERSION.linux-arm64v8.zip"
    run_docker_linux_arm64v8
    #create_zip_file grok_exporter-$VERSION.linux-arm64v8
}

#--------------------------------------------------------------
# main
#--------------------------------------------------------------

case $1 in
    linux-amd64)
        rm -rf dist/*
        release_linux_amd64
        ;;
    linux-arm64v8)
        rm -rf dist/*
        release_linux_arm64v8
        ;;
    *)
        echo 'Usage: ./release.sh <arch>' >&2
        echo 'where <arch> can be:' >&2
        echo '    - linux-amd64' >&2
        echo '    - linux-arm64v8' >&2
        exit -1
esac
