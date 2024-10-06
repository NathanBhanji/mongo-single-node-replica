#!/usr/bin/env bash
set -Eeuo pipefail

NAMESPACE="bhanji"
LIBRARY_FILE="libraryfile"
BUILDX_BUILDER=""
IMAGE_NAME="${NAMESPACE}/mongo-single-node-replica"

mkdir -p build_logs

if [[ ! -f "$LIBRARY_FILE" ]]; then
    echo "Library file '$LIBRARY_FILE' not found!"
    exit 1
fi

echo "Library file found. Parsing..."

trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

TAGS=""
SHAREDTAGS=""
ARCHITECTURES=""
DIRECTORY=""

process_entry() {
    if [[ -n "$TAGS" ]]; then
        echo "Processing entry with Tags: $TAGS"
        
        IFS=',' read -ra TAGS_ARRAY <<< "$TAGS"
        IFS=',' read -ra SHAREDTAGS_ARRAY <<< "$SHAREDTAGS"
        
        for i in "${!TAGS_ARRAY[@]}"; do
            TAGS_ARRAY[$i]=$(trim "${TAGS_ARRAY[$i]}")
        done
        for i in "${!SHAREDTAGS_ARRAY[@]}"; do
            SHAREDTAGS_ARRAY[$i]=$(trim "${SHAREDTAGS_ARRAY[$i]}")
        done
        
        ALL_TAGS=("${TAGS_ARRAY[@]}")
        for shared_tag in "${SHAREDTAGS_ARRAY[@]}"; do
            ALL_TAGS+=("$shared_tag")
        done
        
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
            "$BUILD_CONTEXT" 2>&1 | tee "build_logs/${NAMESPACE}_build_${IMAGE_NAME//\//_}_$(date +%s).log"
        
        echo "Build and push completed for tags: ${ALL_TAGS[*]}"
        echo "--------------------------------------------"
        
        TAGS=""
        SHAREDTAGS=""
        ARCHITECTURES=""
        DIRECTORY=""
    fi
}

while IFS= read -r line; do
    line=$(trim "$line")
    line=$(trim "$line")
    
    [[ -z "$line" ]] && continue
    
    if [[ "$line" == Tags:* ]]; then
        process_entry
        process_entry
        
        TAGS=$(echo "$line" | cut -d':' -f2- | sed 's/, /\n/g' | awk '{print $1}' | paste -sd "," -)
    elif [[ "$line" == SharedTags:* ]]; then
        SHAREDTAGS=$(echo "$line" | cut -d':' -f2- | sed 's/, /\n/g' | awk '{print $1}' | paste -sd "," -)
    elif [[ "$line" == Architectures:* ]]; then
        ARCHITECTURES=$(echo "$line" | cut -d':' -f2- | sed 's/, /\n/g' | awk '{print $1}' | paste -sd "," -)
    elif [[ "$line" == Directory:* ]]; then
        DIRECTORY=$(echo "$line" | cut -d':' -f2- | awk '{print $1}')
    fi
done < "$LIBRARY_FILE"

process_entry

echo "All builds completed successfully!"
