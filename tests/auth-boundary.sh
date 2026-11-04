#!/usr/bin/env bash
# Exercise real mongod processes on an isolated Docker network; no published ports.
set -Eeuo pipefail
image="${MONGO_TEST_IMAGE:-mongo:8.0.29}"
prefix="msnr-auth-$$"
root="$(cd "$(dirname "$0")/.." && pwd)"
fixture="$(mktemp -d)"
cleanup() {
    docker rm -fv "$prefix-db" "$prefix-second" "$prefix-standalone" >/dev/null 2>&1 || :
    docker network rm "$prefix" >/dev/null 2>&1 || :
    rm -rf "$fixture"
}
trap cleanup EXIT
cat > "$fixture/hold.sh" <<'SH'
# Confirm scripts still run with root authorization before holding bootstrap open.
"${mongo[@]}" admin --eval 'if (!db.runCommand({listDatabases:1}).ok) quit(1)' >/dev/null
touch /tmp/bootstrap-ready
while [ ! -e /tmp/bootstrap-release ]; do sleep 1; done
SH
docker network create "$prefix" >/dev/null
docker run -d --name "$prefix-db" --network "$prefix" \
    -v "$root/docker-entrypoint.sh:/usr/local/bin/docker-entrypoint.sh:ro" \
    -v "$fixture/hold.sh:/docker-entrypoint-initdb.d/hold.sh:ro" \
    -e MONGO_REPLICA_SET_NAME=rs0 \
    -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD=test-only-password \
    "$image" >/dev/null
ready=
for ((i=0; i<90; i++)); do
    if docker exec "$prefix-db" test -e /tmp/bootstrap-ready; then ready=1; break; fi
    if [ "$(docker inspect -f '{{.State.Running}}' "$prefix-db")" != true ]; then
        echo 'bootstrap exited before reaching the init script' >&2; exit 1
    fi
    sleep 1
done
[ "$ready" = 1 ]
# A separate container must not be able to create users or write during bootstrap.
docker run --rm --network "$prefix" --entrypoint mongosh "$image" \
    --host "$prefix-db" --quiet --eval '
    for (const action of [
        () => db.getSiblingDB("admin").createUser({user:"attacker",pwd:"test-only",roles:["root"]}),
        () => db.getSiblingDB("attack").t.insertOne({compromised:true})
    ]) {
        let denied = false;
        try { action(); } catch (e) { if (e.code === 13) denied = true; else throw e; }
        if (!denied) throw new Error("unauthenticated operation was accepted during bootstrap");
    }' >/dev/null
docker exec "$prefix-db" touch /tmp/bootstrap-release
for ((i=0; i<60; i++)); do
    if docker exec "$prefix-db" bash -c '[ "$(cat /proc/1/comm)" = mongod ]' \
        && docker exec "$prefix-db" mongosh -u root -p test-only-password --quiet --eval \
        'if (!db.hello().isWritablePrimary) quit(1)' >/dev/null 2>&1; then break; fi
    sleep 1
done
# Check the final server supports authenticated writes and rejects anonymous writes.
docker run --rm --network "$prefix" --entrypoint mongosh "$image" \
    --host "$prefix-db" -u root -p test-only-password --quiet --eval \
    'db.getSiblingDB("verified").t.insertOne({ok:true})' >/dev/null
docker run --rm --network "$prefix" --entrypoint mongosh "$image" \
    --host "$prefix-db" --quiet --eval '
    let denied = false;
    try { db.getSiblingDB("verified").t.findOne(); }
    catch (e) { if (e.code === 13) denied = true; else throw e; }
    if (!denied) throw new Error("anonymous read accepted");' >/dev/null
# Keys are private, independent per database, and stable over a container restart.
first="$(docker exec "$prefix-db" sha256sum /data/db/.replica-set-keyfile)"
[ "$(docker exec "$prefix-db" stat -c %a /data/db/.replica-set-keyfile)" = 600 ]
docker run -d --name "$prefix-second" --network "$prefix" \
    -v "$root/docker-entrypoint.sh:/usr/local/bin/docker-entrypoint.sh:ro" \
    -e MONGO_REPLICA_SET_NAME=rs0 "$image" >/dev/null
for ((i=0; i<30; i++)); do
    if docker exec "$prefix-second" test -s /data/db/.replica-set-keyfile; then break; fi
    sleep 1
done
second="$(docker exec "$prefix-second" sha256sum /data/db/.replica-set-keyfile)"
[ "$first" != "$second" ]
# Knowledge of another database's internal key must not grant __system privileges.
docker cp "$prefix-second:/data/db/.replica-set-keyfile" "$fixture/cross-key" >/dev/null
chmod 600 "$fixture/cross-key"
docker run --rm --network "$prefix" -v "$fixture/cross-key:/cross-key:ro" \
    --entrypoint mongosh "$image" --host "$prefix-db" --quiet --eval '
    let denied = false;
    try {
        db.getSiblingDB("local").auth({user:"__system",
            pwd:fs.readFileSync("/cross-key", "utf8").replace(/\s/g, ""),
            mechanism:"SCRAM-SHA-256"});
    } catch (e) { if (e.code === 18) denied = true; else throw e; }
    if (!denied) throw new Error("another database key authenticated as __system");' >/dev/null
if [ -n "${MONGO_REJECT_KEY_FILE:-}" ]; then
    docker run --rm --network "$prefix" -v "$MONGO_REJECT_KEY_FILE:/legacy-key:ro" \
        --entrypoint mongosh "$image" --host "$prefix-db" --quiet --eval '
        let denied = false;
        try {
            db.getSiblingDB("local").auth({user:"__system",
                pwd:fs.readFileSync("/legacy-key", "utf8").replace(/\s/g, ""),
                mechanism:"SCRAM-SHA-256"});
        } catch (e) { if (e.code === 18) denied = true; else throw e; }
        if (!denied) throw new Error("legacy public key authenticated as __system");' >/dev/null
fi
docker restart "$prefix-db" >/dev/null
[ "$(docker exec "$prefix-db" sha256sum /data/db/.replica-set-keyfile)" = "$first" ]
docker run -d --name "$prefix-standalone" --network "$prefix" \
    -v "$root/docker-entrypoint.sh:/usr/local/bin/docker-entrypoint.sh:ro" \
    -v "$fixture/hold.sh:/docker-entrypoint-initdb.d/hold.sh:ro" \
    -e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD=test-only-password \
    "$image" >/dev/null
ready=
for ((i=0; i<60; i++)); do
    if docker exec "$prefix-standalone" test -e /tmp/bootstrap-ready; then ready=1; break; fi
    sleep 1
done
[ "$ready" = 1 ]
if docker run --rm --network "$prefix" --entrypoint mongosh "$image" \
    "mongodb://$prefix-standalone:27017/?directConnection=true&serverSelectionTimeoutMS=1000" \
    --quiet --eval 'db.getSiblingDB("attack").t.insertOne({compromised:true})' >/dev/null 2>&1; then
    echo 'standalone initialization accepted a network connection' >&2; exit 1
fi
echo 'PASS: bootstrap and runtime authentication; unique private persistent keys'
