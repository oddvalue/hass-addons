# Sourced by the image's /start.sh before Vaultwarden launches.
#
# Moves the vault from /share/vaultwarden (exported over Samba) into this
# add-on's private /data, once. Exits before Vaultwarden starts if /data has
# no database afterwards, so the server can never come up on an empty vault.
SRC=/share/vaultwarden
DST=/data

if [ ! -f "$DST/db.sqlite3" ]; then
    if [ ! -f "$SRC/db.sqlite3" ]; then
        echo "migrate: no database in $DST and none in $SRC, refusing to start" >&2
        exit 1
    fi
    echo "migrate: copying vault from $SRC to $DST"
    cp -a "$SRC/." "$DST/" || { echo "migrate: copy failed, refusing to start" >&2; exit 1; }
    src_sum=$(md5sum "$SRC/db.sqlite3" | cut -d' ' -f1)
    dst_sum=$(md5sum "$DST/db.sqlite3" | cut -d' ' -f1)
    if [ "$src_sum" != "$dst_sum" ]; then
        echo "migrate: checksum mismatch ($src_sum vs $dst_sum), refusing to start" >&2
        exit 1
    fi
    echo "migrate: done, db.sqlite3 md5 $dst_sum"
fi
