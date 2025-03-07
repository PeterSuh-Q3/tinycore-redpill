
mkdir -p /volume1/docker/jellyfin/config
mkdir -p /volume1/docker/jellyfin/cache

curl -kLO# https://repo.jellyfin.org/files/ffmpeg/debian/latest-7.x/amd64/jellyfin-ffmpeg7_7.0.2-9-bookworm_amd64.deb
dpkg-deb -x jellyfin-ffmpeg*.deb temp_dir
mkdir -p /usr/lib/jellyfin-ffmpeg
rsync -av temp_dir/usr/lib/jellyfin-ffmpeg/ /usr/lib/jellyfin-ffmpeg/
cd /usr/lib/jellyfin-ffmpeg
./ffmpeg
