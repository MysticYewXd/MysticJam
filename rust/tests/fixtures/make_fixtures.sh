#!/usr/bin/env bash
# Regenerates the tiny tagged audio fixtures the Rust tests read. Tags and
# lyrics are written by ffmpeg, so the reader is checked against files from
# an independent writer. Formats ffmpeg can't tag with lyrics (WAV, AAC, APE)
# are built and tagged inside the tests instead.
set -euo pipefail
cd "$(dirname "$0")"

tags=(
  -metadata title="Fixture Title"
  -metadata artist="Fixture Artist"
  -metadata album="Fixture Album"
  -metadata album_artist="Fixture Album Artist"
  -metadata genre="Fixture Genre"
  -metadata date="2001-02-03"
  -metadata track="3/9"
  -metadata lyrics="Plain line one
Plain line two"
)
silence=(-f lavfi -t 0.3 -i "anullsrc=r=44100:cl=mono")
q=(-hide_banner -loglevel error -y)
cover_png="$(mktemp --suffix=.png)"
trap 'rm -f "$cover_png"' EXIT
ffmpeg "${q[@]}" -f lavfi -i "color=c=red:s=8x8" -frames:v 1 "$cover_png"
cover=(-i "$cover_png")

# With an embedded cover.
ffmpeg "${q[@]}" "${silence[@]}" "${cover[@]}" -map 0 -map 1 -c:a libmp3lame -b:a 32k -c:v png -disposition:v attached_pic -id3v2_version 3 "${tags[@]}" tagged.mp3
ffmpeg "${q[@]}" "${silence[@]}" "${cover[@]}" -map 0 -map 1 -c:a flac -c:v png -disposition:v attached_pic "${tags[@]}" tagged.flac
ffmpeg "${q[@]}" "${silence[@]}" "${cover[@]}" -map 0 -map 1 -c:a aac -b:a 32k -c:v png -disposition:v attached_pic "${tags[@]}" tagged.m4a
# Without a cover.
ffmpeg "${q[@]}" "${silence[@]}" -c:a libvorbis -q:a 0 "${tags[@]}" tagged.ogg
ffmpeg "${q[@]}" "${silence[@]}" -c:a libopus -b:a 16k "${tags[@]}" tagged.opus
ffmpeg "${q[@]}" "${silence[@]}" -c:a aac -b:a 32k -f mp4 "${tags[@]}" tagged.mp4
# WMA: read by the Dart reader (lofty has no ASF support).
ffmpeg "${q[@]}" "${silence[@]}" -c:a wmav2 -b:a 32k "${tags[@]}" tagged.wma
ffmpeg "${q[@]}" "${silence[@]}" -c:a wmav2 -b:a 32k -metadata title="Synced WMA" -metadata lyrics="[00:01.00]First
[00:02.50]Second" synced.wma
ffmpeg "${q[@]}" "${silence[@]}" -c:a wmav2 -b:a 32k -metadata title="Instrumental WMA" -metadata lyrics="[instrumental:true]" instrumental.wma
ffmpeg "${q[@]}" "${silence[@]}" -c:a wmav2 -b:a 32k -metadata title="Headers WMA" -metadata lyrics="[ti:Song]
[by:Tool]

Words here" headers.wma
# An oversized cover (over 2000 px): shrunk to 1024 px when saved.
ffmpeg "${q[@]}" -f lavfi -i "color=c=blue:s=2400x1800" -frames:v 1 big_cover.png
# Untagged bases, tagged by the tests.
ffmpeg "${q[@]}" -f lavfi -t 0.3 -i "anullsrc=r=8000:cl=mono" -c:a pcm_s16le -map_metadata -1 untagged.wav
ffmpeg "${q[@]}" "${silence[@]}" -c:a aac -b:a 32k -f adts -map_metadata -1 untagged.aac
ffmpeg "${q[@]}" "${silence[@]}" -c:a libmp3lame -b:a 32k -map_metadata -1 -write_xing 0 -id3v2_version 0 untagged.mp3
