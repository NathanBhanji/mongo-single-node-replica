#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="bhanji"
IMAGE_NAME="${NAMESPACE}/mongo-single-node-replica"

trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Read input parameters
TAGS=$(trim "$1")
SHAREDTAGS=$(trim "$2")
ARCHITECTURES=$(trim "$3")
DIRECTORY=$(trim "$4")

echo "Processing entry with Tags: $TAGS"

IFS=',' read -ra TAGS_ARRAY <<< "$TAGS"
IFS=',' read -ra SHAREDTAGS_ARRAY <<< "$SHAREDTAGS"

for i in "${!TAGS_ARRAY[@]}"; do
    TAGS_ARRAY[$i]=$(trim "${TAGS_ARRAY[$i]}")
done
for i in "${!SHAREDTAGS_ARRAY[@]}"; do
    SHAREDTAGS_ARRAY[$i]=$(trim "${SHAREDTAGS_ARRAY[$i]}")
done

ALL_TAGS=("${TAGS_ARRAY[@]}" "${SHAREDTAGS_ARRAY[@]}")

echo "All Tags to be used: ${ALL_TAGS[*]}"

PLATFORM_LIST=""
IFS=',' read -ra ARCH_ARRAY <<< "$ARCHITECTURES"
for arch in "${ARCH_ARRAY[@]}"; do
    arch=$(trim "$arch")
    case "$arch" in
        amd64)
            PLATFORM_LIST+="linux/amd64,"
            ;;
        arm64v8|arm64)
            PLATFORM_LIST+="linux/arm64/v8,"
            ;;
        armv7|arm)
            PLATFORM_LIST+="linux/arm/v7,"
            ;;
        *)
            echo "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
done
PLATFORM_LIST=${PLATFORM_LIST%,}
echo "Mapped Platforms: $PLATFORM_LIST"

TAG_ARGS=()
for tag in "${ALL_TAGS[@]}"; do
    TAG_ARGS+=("-t" "${IMAGE_NAME}:${tag}")
done

BUILD_CONTEXT="./$DIRECTORY"

if [[ ! -d "$BUILD_CONTEXT" ]]; then
    echo "Build context directory '$BUILD_CONTEXT' not found!"
    exit 1
fi

echo "--------------------------------------------"
echo "Building ${IMAGE_NAME} with tags: ${ALL_TAGS[*]}"
echo "Platforms: $PLATFORM_LIST"
echo "Architectures: $ARCHITECTURES"
echo "Directory: $BUILD_CONTEXT"

docker buildx build \
    --builder "$BUILDX_BUILDER" \
    --platform "$PLATFORM_LIST" \
    "${TAG_ARGS[@]}" \
    --push \
    --provenance=false \
    "$BUILD_CONTEXT"

echo "Build and push completed for tags: ${ALL_TAGS[*]}"
echo "--------------------------------------------"
